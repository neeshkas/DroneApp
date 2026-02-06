#!/usr/bin/env python
"""
Simple WebSocket client to test the drone delivery tracking system.
Usage: python test_websocket.py
"""

import asyncio
import json
import os
import hmac
import hashlib
from urllib.request import Request, urlopen
import websockets

API_TOKEN = os.getenv("DRONE_API_TOKEN")
ORDER_TOKEN_SECRET = os.getenv("DRONE_ORDER_TOKEN_SECRET")
BASE_URL = os.getenv("DRONE_API_URL", "http://127.0.0.1:8000")
WS_URL = os.getenv("DRONE_WS_URL", "ws://127.0.0.1:8000/ws/drone")


def _order_token(order_id: str) -> str:
    if not ORDER_TOKEN_SECRET:
        raise RuntimeError("Order token secret not configured")
    return hmac.new(
        ORDER_TOKEN_SECRET.encode("utf-8"),
        order_id.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _start_simulation(order_id: str) -> None:
    if not API_TOKEN:
        raise RuntimeError("API token not configured")

    payload = {
        "orderId": order_id,
        "start_lat": 43.235,
        "start_lng": 76.88,
        "end_lat": 43.24,
        "end_lng": 76.90,
    }
    data = json.dumps(payload).encode("utf-8")
    req = Request(
        f"{BASE_URL.rstrip('/')}/simulation/start",
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_TOKEN}",
            "X-Order-Token": _order_token(order_id),
        },
    )
    with urlopen(req, timeout=5) as resp:
        resp.read()


async def test_websocket():
    order_id = "TEST-ORDER-001"
    _start_simulation(order_id)

    if not API_TOKEN:
        raise RuntimeError("API token not configured")

    uri = f"{WS_URL}?token={API_TOKEN}"

    async with websockets.connect(uri) as websocket:
        print(f"Connected to {uri}")

        message = {
            "type": "start_tracking",
            "orderId": order_id,
            "orderToken": _order_token(order_id),
        }

        await websocket.send(json.dumps(message))
        print(f"Sent: {message}")

        update_count = 0
        while True:
            try:
                response = await asyncio.wait_for(websocket.recv(), timeout=10)
                data = json.loads(response)

                if data.get("type") == "drone_position":
                    update_count += 1
                    print(f"\nUpdate #{update_count}:")
                    print(f"  Position: ({data['lat']:.6f}, {data['lng']:.6f})")
                    print(f"  Progress: {data['progress']*100:.1f}%")
                    print(f"  Status: {data['status']}")
                    print(f"  Delivered: {data['delivered']}")

                    if data["delivered"]:
                        print("\nDelivery complete!")
                        break

            except asyncio.TimeoutError:
                print("\nNo message received for 10 seconds")
                break
            except Exception as exc:
                print(f"\nError: {exc}")
                break


if __name__ == "__main__":
    asyncio.run(test_websocket())
