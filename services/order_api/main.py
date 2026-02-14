from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import sqlite3
import time
from typing import List, Optional
from pathlib import Path
import json
import os
import uuid
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import jwt

DB_PATH = Path(__file__).parent / "order_api.db"
NOMINATIM_BASE = "https://nominatim.openstreetmap.org"
ALMATY_VIEWBOX = "76.7,43.35,77.1,43.0"
GEOCODE_TTL_SECONDS = 300
SIMULATOR_URL = os.getenv("SIMULATOR_URL", "http://127.0.0.1:8001")
JWT_PRIVATE_KEY = os.getenv("JWT_PRIVATE_KEY")
JWT_PUBLIC_KEY = os.getenv("JWT_PUBLIC_KEY")
JWT_PRIVATE_KEY_PATH = os.getenv("JWT_PRIVATE_KEY_PATH")
JWT_PUBLIC_KEY_PATH = os.getenv("JWT_PUBLIC_KEY_PATH")
JWT_ISSUER = os.getenv("JWT_ISSUER", "droneapp")
JWT_AUDIENCE = os.getenv("JWT_AUDIENCE", "droneapp-clients")
ACCESS_TTL_SECONDS = int(os.getenv("ACCESS_TTL_SECONDS", "900"))
REFRESH_TTL_SECONDS = int(os.getenv("REFRESH_TTL_SECONDS", "2592000"))
CORS_ALLOW_ORIGINS = os.getenv("CORS_ALLOW_ORIGINS", "*")

IMAGE_URLS = [
    "https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1543362906-acfc16c67564?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1464965911861-746a04b4bca6?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1481931098730-318b6f776db0?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1473093295043-cdd812d0e601?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1506807803488-8eafc15316c0?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1505252585461-04db1eb84625?auto=format&fit=crop&w=800&q=60",
    "https://images.unsplash.com/photo-1526318472351-c75fcf070305?auto=format&fit=crop&w=800&q=60",
]


class Store(BaseModel):
    id: str
    name: str
    address: str
    latitude: float
    longitude: float


class Product(BaseModel):
    id: str
    storeId: str
    title: str
    price: float
    weight: float
    imageUrl: str


class DeliveryCreateIn(BaseModel):
    store_id: str
    start_lat: float
    start_lng: float
    end_lat: float
    end_lng: float


class DeliveryCreateOut(BaseModel):
    delivery_id: str
    tracking_access_token: str
    tracking_refresh_token: str


class RefreshIn(BaseModel):
    refresh_token: str


class RefreshOut(BaseModel):
    access_token: str


app = FastAPI(title="Order API")

allow_origins = [o.strip() for o in CORS_ALLOW_ORIGINS.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins if allow_origins else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

_geocode_cache: dict[str, tuple[float, dict | list]] = {}


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("PRAGMA foreign_keys = ON")
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS stores(
          id TEXT PRIMARY KEY,
          name TEXT,
          address TEXT,
          latitude REAL,
          longitude REAL
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS products(
          id TEXT PRIMARY KEY,
          store_id TEXT,
          title TEXT,
          price REAL,
          weight REAL,
          image_url TEXT
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS deliveries(
          delivery_id TEXT PRIMARY KEY,
          store_id TEXT,
          start_lat REAL,
          start_lng REAL,
          end_lat REAL,
          end_lng REAL,
          status TEXT,
          created_at REAL
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS refresh_tokens(
          jti TEXT PRIMARY KEY,
          delivery_id TEXT,
          expires_at REAL,
          revoked INTEGER DEFAULT 0
        )
        """
    )
    cur.execute("SELECT COUNT(*) FROM stores")
    if cur.fetchone()[0] == 0:
        stores_rows = []
        products_rows = []
        for i in range(10):
            base_lat = 43.235 + i * 0.002
            base_lng = 76.88 + i * 0.003
            sid = f"s{i+1}"
            store_name = f"AeroMart {i+1}"
            stores_rows.append((sid, store_name, f"Kaskelen Ave {50+i}", base_lat, base_lng))
            for j in range(10):
                pid = f"{sid}_p{j+1}"
                products_rows.append(
                    (
                        pid,
                        sid,
                        f"Essentials Pack {j+1} - {store_name}",
                        1500 + j * 150,
                        200 + j * 30,
                        IMAGE_URLS[j % len(IMAGE_URLS)],
                    )
                )
        cur.executemany("INSERT INTO stores VALUES (?,?,?,?,?)", stores_rows)
        cur.executemany("INSERT INTO products VALUES (?,?,?,?,?,?)", products_rows)
        conn.commit()
    conn.close()


init_db()


def _cache_get(key: str) -> dict | list | None:
    now = time.time()
    cached = _geocode_cache.get(key)
    if cached is None:
        return None
    expires_at, payload = cached
    if expires_at < now:
        _geocode_cache.pop(key, None)
        return None
    return payload


def _cache_set(key: str, payload: dict | list) -> None:
    _geocode_cache[key] = (time.time() + GEOCODE_TTL_SECONDS, payload)


def _nominatim_get(path: str, params: dict) -> dict | list:
    cache_key = f"{path}?{urlencode(params)}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached

    url = f"{NOMINATIM_BASE}{cache_key}"
    req = Request(
        url,
        headers={
            "User-Agent": "DroneApp/1.0 (local demo)",
            "Accept-Language": "ru",
        },
    )
    with urlopen(req, timeout=10) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
        _cache_set(cache_key, payload)
        return payload


def _read_key_value(value: str | None, path: str | None, env_name: str) -> str:
    if value:
        return value.replace("\\n", "\n")
    if path:
        try:
            return Path(path).read_text(encoding="utf-8")
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Failed to read {env_name} from {path}: {exc}")
    raise HTTPException(status_code=500, detail=f"{env_name} not configured")


def _load_private_key() -> str:
    return _read_key_value(JWT_PRIVATE_KEY, JWT_PRIVATE_KEY_PATH, "JWT_PRIVATE_KEY")


def _load_public_key() -> str:
    return _read_key_value(JWT_PUBLIC_KEY, JWT_PUBLIC_KEY_PATH, "JWT_PUBLIC_KEY")


def _issue_access_token(delivery_id: str, role: str, scopes: list[str]) -> str:
    now = int(time.time())
    payload = {
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
        "sub": delivery_id,
        "role": role,
        "scopes": scopes,
        "type": "access",
        "iat": now,
        "nbf": now,
        "exp": now + ACCESS_TTL_SECONDS,
    }
    return jwt.encode(payload, _load_private_key(), algorithm="RS256")


def _issue_refresh_token(delivery_id: str) -> str:
    now = int(time.time())
    jti = str(uuid.uuid4())
    payload = {
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
        "sub": delivery_id,
        "jti": jti,
        "type": "refresh",
        "iat": now,
        "nbf": now,
        "exp": now + REFRESH_TTL_SECONDS,
    }
    token = jwt.encode(payload, _load_private_key(), algorithm="RS256")
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO refresh_tokens (jti, delivery_id, expires_at, revoked) VALUES (?, ?, ?, 0)",
            (jti, delivery_id, now + REFRESH_TTL_SECONDS),
        )
        conn.commit()
    finally:
        conn.close()
    return token


def _decode_token(token: str) -> dict:
    return jwt.decode(
        token,
        _load_public_key(),
        algorithms=["RS256"],
        audience=JWT_AUDIENCE,
        issuer=JWT_ISSUER,
    )


def _start_simulation(payload: dict) -> None:
    data = json.dumps(payload).encode("utf-8")
    token = _issue_access_token(payload["delivery_id"], "operator", ["simulator:start"])
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    req = Request(
        f"{SIMULATOR_URL.rstrip('/')}/start",
        data=data,
        headers=headers,
    )
    with urlopen(req, timeout=5) as resp:
        resp.read()


@app.post("/deliveries", response_model=DeliveryCreateOut)
def create_delivery(payload: DeliveryCreateIn):
    delivery_id = f"DLV-{uuid.uuid4().hex[:10]}"
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO deliveries (delivery_id, store_id, start_lat, start_lng, end_lat, end_lng, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                delivery_id,
                payload.store_id,
                payload.start_lat,
                payload.start_lng,
                payload.end_lat,
                payload.end_lng,
                "CREATED",
                time.time(),
            ),
        )
        conn.commit()
    finally:
        conn.close()

    _start_simulation(
        {
            "delivery_id": delivery_id,
            "start_lat": payload.start_lat,
            "start_lng": payload.start_lng,
            "end_lat": payload.end_lat,
            "end_lng": payload.end_lng,
        }
    )

    access_token = _issue_access_token(delivery_id, "customer", ["tracking:read"])
    refresh_token = _issue_refresh_token(delivery_id)
    return DeliveryCreateOut(
        delivery_id=delivery_id,
        tracking_access_token=access_token,
        tracking_refresh_token=refresh_token,
    )


@app.post("/auth/refresh", response_model=RefreshOut)
def refresh_access_token(payload: RefreshIn):
    try:
        claims = _decode_token(payload.refresh_token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    if claims.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    jti = claims.get("jti")
    delivery_id = claims.get("sub")
    if not jti or not delivery_id:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    conn = get_conn()
    try:
        cur = conn.cursor()
        row = cur.execute(
            "SELECT revoked, expires_at FROM refresh_tokens WHERE jti = ?",
            (jti,),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=401, detail="Refresh token not found")
        if row["revoked"]:
            raise HTTPException(status_code=401, detail="Refresh token revoked")
        if row["expires_at"] < time.time():
            raise HTTPException(status_code=401, detail="Refresh token expired")
    finally:
        conn.close()

    access_token = _issue_access_token(delivery_id, "customer", ["tracking:read"])
    return RefreshOut(access_token=access_token)


@app.get("/stores", response_model=List[Store])
def get_stores():
    conn = get_conn()
    cur = conn.cursor()
    rows = cur.execute("SELECT id, name, address, latitude, longitude FROM stores").fetchall()
    conn.close()
    return [Store(**dict(r)) for r in rows]


@app.get("/products", response_model=List[Product])
def get_products(store_id: Optional[str] = None):
    conn = get_conn()
    cur = conn.cursor()
    if store_id:
        rows = cur.execute(
            "SELECT id, store_id as storeId, title, price, weight, image_url as imageUrl FROM products WHERE store_id = ?",
            (store_id,),
        ).fetchall()
    else:
        rows = cur.execute(
            "SELECT id, store_id as storeId, title, price, weight, image_url as imageUrl FROM products",
        ).fetchall()
    conn.close()
    return [Product(**dict(r)) for r in rows]


def _normalize_query(q: str) -> str:
    value = q.strip()
    if not value:
        return value
    lower = value.lower()
    if "алматы" in lower or "almaty" in lower:
        return value
    return f"{value}, Алматы, Казахстан"


@app.get("/geocode")
def geocode(q: str):
    try:
        params = {
            "format": "jsonv2",
            "q": _normalize_query(q),
            "limit": 5,
            "viewbox": ALMATY_VIEWBOX,
            "bounded": 1,
            "addressdetails": 1,
            "countrycodes": "kz",
        }
        return _nominatim_get("/search", params)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Geocoding failed: {exc}")


@app.get("/reverse-geocode")
def reverse_geocode(lat: float, lng: float):
    try:
        params = {
            "format": "jsonv2",
            "lat": lat,
            "lon": lng,
            "zoom": 18,
            "addressdetails": 1,
        }
        return _nominatim_get("/reverse", params)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Reverse geocoding failed: {exc}")


@app.get("/")
def root():
    return {"status": "ok"}
