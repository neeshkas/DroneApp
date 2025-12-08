import random
import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "drone.db"

STORE_NAMES = [
    "Магазин Центр",
    "Магазин Восток",
    "Магазин Запад",
    "Магазин Север",
    "Магазин Юг",
    "Маркет А",
    "Маркет B",
    "Маркет C",
    "Маркет D",
    "Маркет E",
    "ДронМаркет 1",
    "ДронМаркет 2",
]

PRODUCT_TITLES = [
    "Кофе зерновой",
    "Чай зелёный",
    "Батончик энергетический",
    "Шоколад",
    "Сок апельсиновый",
    "Вода негаз",
    "Вода газ",
    "Орехи микс",
    "Чипсы",
    "Печенье овсяное",
    "Творожок",
    "Йогурт",
    "Сэндвич",
    "Салат",
    "Суп готовый",
]

IMAGE_URL = "https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=400&q=60"


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def ensure_tables(conn: sqlite3.Connection) -> None:
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
    conn.commit()


def wipe(conn: sqlite3.Connection) -> None:
    cur = conn.cursor()
    cur.execute("DELETE FROM products")
    cur.execute("DELETE FROM stores")
    conn.commit()


def generate_data():
    stores = []
    products = []
    base_lat, base_lng = 43.2350, 76.8800

    for idx, name in enumerate(STORE_NAMES, start=1):
        lat = base_lat + idx * 0.0025
        lng = base_lng + idx * 0.0035
        sid = f"s{idx:02d}"
        stores.append((sid, name, f"Алматы, ул. Абая {40 + idx}", lat, lng))

        for p_idx, title in enumerate(PRODUCT_TITLES, start=1):
            pid = f"{sid}_p{p_idx:02d}"
            price = 1200 + 150 * p_idx + random.randint(-50, 80)
            weight = 150 + 25 * p_idx + random.randint(-10, 40)
            products.append((pid, sid, f"{title} · {name}", price, weight, IMAGE_URL))

    return stores, products


def seed():
    conn = get_conn()
    ensure_tables(conn)
    wipe(conn)
    stores, products = generate_data()
    cur = conn.cursor()
    cur.executemany("INSERT INTO stores VALUES (?,?,?,?,?)", stores)
    cur.executemany("INSERT INTO products VALUES (?,?,?,?,?,?)", products)
    conn.commit()
    conn.close()
    return len(stores), len(products)


if __name__ == "__main__":
    s_count, p_count = seed()
    print(f"Seeded {s_count} stores and {p_count} products into {DB_PATH}")
