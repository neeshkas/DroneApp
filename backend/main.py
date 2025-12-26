from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import sqlite3
import time
from typing import List
from pathlib import Path

DB_PATH = Path(__file__).parent / "drone.db"
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

# In-memory state to avoid teleport/loop for each order id
order_states: dict[str, dict] = {}


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
