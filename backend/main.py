from fastapi import FastAPI, WebSocket, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import sqlite3
import time
from typing import List
from pathlib import Path
import asyncio
import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen

DB_PATH = Path(__file__).parent / "drone.db"
NOMINATIM_BASE = "https://nominatim.openstreetmap.org"
ALMATY_VIEWBOX = "76.7,43.35,77.1,43.0"
GEOCODE_TTL_SECONDS = 300
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


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_conn()
    cur = conn.cursor()
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


app = FastAPI(title="DroneDelivery mock backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

init_db()

# In-memory state
order_states: dict[str, dict] = {}
active_flights: dict[str, asyncio.Task] = {}
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


@app.get("/geocode")
def geocode(q: str):
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
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Reverse geocoding failed: {e}")


@app.get("/stores", response_model=List[Store])
def get_stores():
    conn = get_conn()
    cur = conn.cursor()
    rows = cur.execute("SELECT id, name, address, latitude, longitude FROM stores").fetchall()
    conn.close()
    return [Store(**dict(r)) for r in rows]


@app.get("/products", response_model=List[Product])
def get_products(store_id: str | None = None):
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
def drone_position(
    orderId: str,
    start_lat: float = 43.238949,
    start_lng: float = 76.889709,
    end_lat: float = 43.2409,
    end_lng: float = 76.9170,
):
    """Legacy HTTP endpoint for drone position (kept for compatibility)"""
    period = 20.0
    now = time.time()

    state = order_states.get(orderId)
    if state is None:
        state = {
            "start_time": now,
            "start": (start_lat, start_lng),
            "end": (end_lat, end_lng),
            "delivered": False,
        }
        order_states[orderId] = state

    if state["delivered"]:
        end = state["end"]
        return {"lat": end[0], "lng": end[1], "delivered": True}

    elapsed = now - state["start_time"]
    progress = min(1.0, elapsed / period)
    start = state["start"]
    end = state["end"]

    lat = start[0] + (end[0] - start[0]) * progress
    lng = start[1] + (end[1] - start[1]) * progress

    delivered = progress >= 1.0
    if delivered:
        state["delivered"] = True

    return {"lat": lat, "lng": lng, "delivered": delivered}


@app.get("/")
def root():
    return {"status": "ok"}


@app.websocket("/ws/drone")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    client_id = f"client_{id(websocket)}"
    print(f"WebSocket client connected: {client_id}")

    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)

            if message.get("type") == "start_tracking":
                await handle_start_tracking(client_id, websocket, message)
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        if client_id in active_flights:
            active_flights[client_id].cancel()
            del active_flights[client_id]
        print(f"WebSocket client disconnected: {client_id}")


async def handle_start_tracking(client_id: str, websocket: WebSocket, message: dict):
    order_id = message.get("orderId")
    start_lat = float(message.get("start_lat", 43.238949))
    start_lng = float(message.get("start_lng", 76.889709))
    end_lat = float(message.get("end_lat", 43.2409))
    end_lng = float(message.get("end_lng", 76.9170))

    if not order_id:
        await websocket.send_text(json.dumps({"type": "error", "message": "orderId is required"}))
        return

    order_states[order_id] = {
        "start_time": time.time(),
        "start": (start_lat, start_lng),
        "end": (end_lat, end_lng),
        "delivered": False,
        "client_id": client_id,
    }

    if client_id in active_flights:
        active_flights[client_id].cancel()

    active_flights[client_id] = asyncio.create_task(
        simulate_flight(client_id, websocket, order_id, start_lat, start_lng, end_lat, end_lng)
    )


async def simulate_flight(
    client_id: str,
    websocket: WebSocket,
    order_id: str,
    start_lat: float,
    start_lng: float,
    end_lat: float,
    end_lng: float,
):
    """
    Simulate drone flight by sending coordinates every 5 seconds.
    Total flight time is 60 seconds.
    """
    flight_duration = 30.0
    update_interval = 5.0
    start_time = time.time()

    try:
        while True:
            now = time.time()
            elapsed = now - start_time
            progress = min(1.0, elapsed / flight_duration)

            lat = start_lat + (end_lat - start_lat) * progress
            lng = start_lng + (end_lng - start_lng) * progress
            delivered = progress >= 1.0

            if delivered:
                status = "Delivered"
            elif progress < 0.2:
                status = "Taking off..."
            elif progress < 0.8:
                status = "In flight"
            else:
                status = "Approaching destination..."

            await websocket.send_text(
                json.dumps(
                    {
                        "type": "drone_position",
                        "lat": lat,
                        "lng": lng,
                        "delivered": delivered,
                        "progress": progress,
                        "status": status,
                        "orderId": order_id,
                    }
                )
            )

            state = order_states.get(order_id)
            if state:
                state["delivered"] = delivered

            if delivered:
                print(f"Order {order_id} delivered to client {client_id}")
                break

            await asyncio.sleep(update_interval)
    except asyncio.CancelledError:
        print(f"Flight task cancelled for order {order_id}")
    except Exception as e:
        print(f"Error in flight simulation: {e}")
