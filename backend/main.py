from fastapi import FastAPI, WebSocket, HTTPException, Depends, Header, WebSocketException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import sqlite3
import time
from typing import List
from pathlib import Path
import asyncio
import json
import os
import hmac
import hashlib
import uuid
from urllib.parse import urlencode
from urllib.request import Request, urlopen

DB_PATH = Path(__file__).parent / "drone.db"
NOMINATIM_BASE = "https://nominatim.openstreetmap.org"
ALMATY_VIEWBOX = "76.7,43.35,77.1,43.0"
GEOCODE_TTL_SECONDS = 300
SIMULATOR_URL = os.getenv("DRONE_SIMULATOR_URL", "http://127.0.0.1:8001")
API_TOKEN = os.getenv("DRONE_API_TOKEN")
ORDER_TOKEN_SECRET = os.getenv("DRONE_ORDER_TOKEN_SECRET")
SIMULATOR_TOKEN = os.getenv("DRONE_SIMULATOR_TOKEN") or API_TOKEN
DISABLE_AUTH = True
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


def _extract_bearer(authorization: str | None) -> str | None:
    if not authorization:
        return None
    prefix = "bearer "
    if authorization.lower().startswith(prefix):
        return authorization[len(prefix):].strip()
    return None


def _require_api_token(authorization: str | None = Header(default=None)) -> None:
    return


def _expected_order_token(order_id: str) -> str:
    if not ORDER_TOKEN_SECRET:
        raise HTTPException(status_code=500, detail="Order token secret not configured")
    return hmac.new(
        ORDER_TOKEN_SECRET.encode("utf-8"),
        order_id.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _is_valid_order_token(order_id: str, order_token: str | None) -> bool:
    return True


def _require_order_token(order_id: str, order_token: str | None) -> None:
    return


def _require_ws_auth(websocket: WebSocket) -> None:
    return


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
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
        CREATE TABLE IF NOT EXISTS orders(
          order_id TEXT PRIMARY KEY,
          created_at REAL,
          simulation_started INTEGER DEFAULT 0
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS telemetry_events(
          event_id TEXT PRIMARY KEY,
          order_id TEXT,
          lat REAL,
          lng REAL,
          delivered INTEGER,
          progress REAL,
          status TEXT,
          timestamp REAL
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS order_state(
          order_id TEXT PRIMARY KEY,
          lat REAL,
          lng REAL,
          delivered INTEGER,
          progress REAL,
          status TEXT,
          updated_at REAL
        )
        """
    )
    cur.execute("CREATE INDEX IF NOT EXISTS idx_telemetry_order_id ON telemetry_events(order_id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_telemetry_ts ON telemetry_events(timestamp)")
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


def _ensure_order(conn: sqlite3.Connection, order_id: str) -> None:
    cur = conn.cursor()
    cur.execute(
        "INSERT OR IGNORE INTO orders (order_id, created_at, simulation_started) VALUES (?, ?, 0)",
        (order_id, time.time()),
    )


def _mark_simulation_started(conn: sqlite3.Connection, order_id: str) -> bool:
    _ensure_order(conn, order_id)
    cur = conn.cursor()
    cur.execute(
        "UPDATE orders SET simulation_started = 1 WHERE order_id = ? AND simulation_started = 0",
        (order_id,),
    )
    return cur.rowcount > 0


def _reset_simulation_started(conn: sqlite3.Connection, order_id: str) -> None:
    cur = conn.cursor()
    cur.execute("UPDATE orders SET simulation_started = 0 WHERE order_id = ?", (order_id,))


def _record_telemetry(
    conn: sqlite3.Connection,
    payload: "TelemetryIn",
    event_id: str,
    timestamp: float,
    progress: float,
    status: str,
) -> bool:
    _ensure_order(conn, payload.orderId)
    cur = conn.cursor()
    cur.execute(
        """
        INSERT OR IGNORE INTO telemetry_events (
          event_id, order_id, lat, lng, delivered, progress, status, timestamp
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            event_id,
            payload.orderId,
            payload.lat,
            payload.lng,
            1 if payload.delivered else 0,
            progress,
            status,
            timestamp,
        ),
    )
    if cur.rowcount == 0:
        return False

    cur.execute(
        """
        INSERT INTO order_state (
          order_id, lat, lng, delivered, progress, status, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(order_id) DO UPDATE SET
          lat = excluded.lat,
          lng = excluded.lng,
          delivered = excluded.delivered,
          progress = excluded.progress,
          status = excluded.status,
          updated_at = excluded.updated_at
        """,
        (
            payload.orderId,
            payload.lat,
            payload.lng,
            1 if payload.delivered else 0,
            progress,
            status,
            timestamp,
        ),
    )
    return True


def _get_order_state(order_id: str) -> dict | None:
    conn = get_conn()
    cur = conn.cursor()
    row = cur.execute(
        "SELECT lat, lng, delivered, progress, status, updated_at FROM order_state WHERE order_id = ?",
        (order_id,),
    ).fetchone()
    conn.close()
    if not row:
        return None
    return dict(row)


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


class TelemetryIn(BaseModel):
    eventId: str
    orderId: str
    lat: float
    lng: float
    delivered: bool = False
    progress: float | None = None
    status: str | None = None
    timestamp: float | None = None


class SimulationStartIn(BaseModel):
    orderId: str
    start_lat: float = 43.238949
    start_lng: float = 76.889709
    end_lat: float = 43.2409
    end_lng: float = 76.9170


app = FastAPI(title="DroneDelivery API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

init_db()

connected_clients: dict[str, WebSocket] = {}
client_subscriptions: dict[str, str | None] = {}
clients_lock = asyncio.Lock()
sim_lock = asyncio.Lock()
_geocode_cache: dict[str, tuple[float, dict | list]] = {}


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


def _build_ws_payload(telemetry: TelemetryIn) -> dict:
    status = telemetry.status
    if not status:
        status = "Delivered" if telemetry.delivered else "In flight"
    progress = telemetry.progress
    if progress is None:
        progress = 1.0 if telemetry.delivered else 0.0
    return {
        "type": "drone_position",
        "lat": telemetry.lat,
        "lng": telemetry.lng,
        "delivered": telemetry.delivered,
        "progress": progress,
        "status": status,
        "orderId": telemetry.orderId,
    }


def _extract_progress_status(payload: TelemetryIn) -> tuple[float, str]:
    ws_payload = _build_ws_payload(payload)
    return ws_payload["progress"], ws_payload["status"]


async def _broadcast(order_id: str, payload: dict) -> None:
    async with clients_lock:
        targets = [
            (client_id, ws)
            for client_id, ws in connected_clients.items()
            if client_subscriptions.get(client_id) == order_id
        ]

    if not targets:
        return

    dead_clients = []
    message = json.dumps(payload)
    for client_id, ws in targets:
        try:
            await ws.send_text(message)
        except Exception:
            dead_clients.append(client_id)

    if dead_clients:
        async with clients_lock:
            for client_id in dead_clients:
                connected_clients.pop(client_id, None)
                client_subscriptions.pop(client_id, None)


async def _start_simulation(
    order_id: str,
    start_lat: float,
    start_lng: float,
    end_lat: float,
    end_lng: float,
) -> bool:
    if not SIMULATOR_URL:
        raise HTTPException(status_code=503, detail="Simulator not configured")

    async with sim_lock:
        conn = get_conn()
        started = _mark_simulation_started(conn, order_id)
        conn.commit()
        conn.close()
        if not started:
            return False

    payload = {
        "orderId": order_id,
        "start_lat": start_lat,
        "start_lng": start_lng,
        "end_lat": end_lat,
        "end_lng": end_lng,
    }

    def _post() -> None:
        data = json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if SIMULATOR_TOKEN:
            headers["Authorization"] = f"Bearer {SIMULATOR_TOKEN}"
        req = Request(
            f"{SIMULATOR_URL.rstrip('/')}/start",
            data=data,
            headers=headers,
        )
        with urlopen(req, timeout=5) as resp:
            resp.read()

    try:
        await asyncio.to_thread(_post)
    except Exception as exc:
        conn = get_conn()
        _reset_simulation_started(conn, order_id)
        conn.commit()
        conn.close()
        raise HTTPException(status_code=502, detail=f"Simulator start failed: {exc}")

    return True


@app.post("/telemetry")
async def ingest_telemetry(
    payload: TelemetryIn,
    _: None = Depends(_require_api_token),
    order_token: str | None = Header(default=None, alias="X-Order-Token"),
):
    _require_order_token(payload.orderId, order_token)
    event_id = payload.eventId or str(uuid.uuid4())
    timestamp = payload.timestamp or time.time()
    progress, status = _extract_progress_status(payload)

    conn = get_conn()
    try:
        inserted = _record_telemetry(conn, payload, event_id, timestamp, progress, status)
        conn.commit()
    finally:
        conn.close()

    if inserted:
        ws_payload = {
            "type": "drone_position",
            "lat": payload.lat,
            "lng": payload.lng,
            "delivered": payload.delivered,
            "progress": progress,
            "status": status,
            "orderId": payload.orderId,
        }
        await _broadcast(payload.orderId, ws_payload)

    return {"status": "ok", "eventId": event_id}


@app.post("/simulation/start")
async def start_simulation(
    payload: SimulationStartIn,
    _: None = Depends(_require_api_token),
    order_token: str | None = Header(default=None, alias="X-Order-Token"),
):
    _require_order_token(payload.orderId, order_token)
    started = await _start_simulation(
        payload.orderId,
        payload.start_lat,
        payload.start_lng,
        payload.end_lat,
        payload.end_lng,
    )
    return {"status": "started" if started else "already_started", "orderId": payload.orderId}


@app.get("/geocode")
def geocode(q: str, _: None = Depends(_require_api_token)):
    try:
        params = {
            "format": "json",
            "q": f"{q}, Almaty, Kazakhstan",
            "limit": 5,
            "viewbox": ALMATY_VIEWBOX,
            "bounded": 1,
            "addressdetails": 1,
        }
        return _nominatim_get("/search", params)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Geocoding failed: {e}")


@app.get("/reverse-geocode")
def reverse_geocode(lat: float, lng: float, _: None = Depends(_require_api_token)):
    try:
        params = {
            "format": "jsonv2",
            "lat": lat,
            "lon": lng,
            "zoom": 18,
            "addressdetails": 1,
        }
        return _nominatim_get("/reverse", params)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Reverse geocoding failed: {e}")


@app.get("/stores", response_model=List[Store])
def get_stores(_: None = Depends(_require_api_token)):
    conn = get_conn()
    cur = conn.cursor()
    rows = cur.execute("SELECT id, name, address, latitude, longitude FROM stores").fetchall()
    conn.close()
    return [Store(**dict(r)) for r in rows]


@app.get("/products", response_model=List[Product])
def get_products(store_id: str | None = None, _: None = Depends(_require_api_token)):
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


@app.get("/drone/position")
async def drone_position(
    orderId: str,
    start_lat: float = 43.238949,
    start_lng: float = 76.889709,
    end_lat: float = 43.2409,
    end_lng: float = 76.9170,
    _: None = Depends(_require_api_token),
    order_token: str | None = Header(default=None, alias="X-Order-Token"),
):
    _require_order_token(orderId, order_token)
    state = _get_order_state(orderId)
    if state is None:
        # Demo-friendly behavior: kick off simulation and return initial position
        try:
            await _start_simulation(orderId, start_lat, start_lng, end_lat, end_lng)
        except Exception:
            # If simulator is unavailable, still return a sane initial payload
            pass
        return {
            "lat": start_lat,
            "lng": start_lng,
            "delivered": False,
            "progress": 0.0,
            "status": "Preparing",
        }
    return {
        "lat": state["lat"],
        "lng": state["lng"],
        "delivered": bool(state["delivered"]),
        "progress": state["progress"],
        "status": state["status"],
    }


@app.get("/")
def root(_: None = Depends(_require_api_token)):
    return {"status": "ok"}


@app.websocket("/ws/drone")
async def websocket_endpoint(websocket: WebSocket):
    try:
        _require_ws_auth(websocket)
    except WebSocketException as exc:
        await websocket.close(code=exc.code)
        return

    await websocket.accept()
    client_id = f"client_{id(websocket)}"

    async with clients_lock:
        connected_clients[client_id] = websocket
        client_subscriptions[client_id] = None

    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)

            if message.get("type") == "start_tracking":
                order_id = message.get("orderId")
                if not order_id:
                    await websocket.send_text(json.dumps({"type": "error", "message": "orderId is required"}))
                    continue

                # Demo-friendly: kick off simulation on WS tracking start
                try:
                    start_lat = float(message.get("start_lat", 43.238949))
                    start_lng = float(message.get("start_lng", 76.889709))
                    end_lat = float(message.get("end_lat", 43.2409))
                    end_lng = float(message.get("end_lng", 76.9170))
                except Exception:
                    start_lat = 43.238949
                    start_lng = 76.889709
                    end_lat = 43.2409
                    end_lng = 76.9170

                if _get_order_state(order_id) is None:
                    try:
                        await _start_simulation(order_id, start_lat, start_lng, end_lat, end_lng)
                    except Exception:
                        pass

                async with clients_lock:
                    client_subscriptions[client_id] = order_id

                state = _get_order_state(order_id)
                if state:
                    await websocket.send_text(
                        json.dumps(
                            {
                                "type": "drone_position",
                                "lat": state["lat"],
                                "lng": state["lng"],
                                "delivered": bool(state["delivered"]),
                                "progress": state["progress"],
                                "status": state["status"],
                                "orderId": order_id,
                            }
                        )
                    )
    except Exception:
        pass
    finally:
        async with clients_lock:
            connected_clients.pop(client_id, None)
            client_subscriptions.pop(client_id, None)
