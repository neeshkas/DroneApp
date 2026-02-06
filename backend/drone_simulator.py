from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel
import asyncio
import json
import os
import time
import hmac
import hashlib
import uuid
from urllib.request import Request, urlopen

DRONE_API_URL = os.getenv("DRONE_API_URL", "http://127.0.0.1:8000")
API_TOKEN = os.getenv("DRONE_API_TOKEN")
ORDER_TOKEN_SECRET = os.getenv("DRONE_ORDER_TOKEN_SECRET")
SIMULATOR_TOKEN = os.getenv("DRONE_SIMULATOR_TOKEN") or API_TOKEN
DISABLE_AUTH = True

app = FastAPI(title="Drone Simulator")

active_flights: dict[str, asyncio.Task] = {}


class StartRequest(BaseModel):
    orderId: str
    start_lat: float = 43.238949
    start_lng: float = 76.889709
    end_lat: float = 43.2409
    end_lng: float = 76.9170
    duration_sec: float = 30.0
    update_interval_sec: float = 5.0


def _extract_bearer(authorization: str | None) -> str | None:
    if not authorization:
        return None
    prefix = "bearer "
    if authorization.lower().startswith(prefix):
        return authorization[len(prefix):].strip()
    return None


def _require_simulator_token(authorization: str | None = Header(default=None)) -> None:
    return


def _order_token(order_id: str) -> str:
    if not ORDER_TOKEN_SECRET:
        raise RuntimeError("Order token secret not configured")
    return hmac.new(
        ORDER_TOKEN_SECRET.encode("utf-8"),
        order_id.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _build_status(progress: float, delivered: bool) -> str:
    if delivered:
        return "Delivered"
    if progress < 0.2:
        return "Taking off..."
    if progress < 0.8:
        return "In flight"
    return "Approaching destination..."


async def _send_telemetry(payload: dict) -> None:
    def _post() -> None:
        data = json.dumps(payload).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
        }
        if API_TOKEN:
            headers["Authorization"] = f"Bearer {API_TOKEN}"
        if ORDER_TOKEN_SECRET:
            headers["X-Order-Token"] = _order_token(payload["orderId"])
        req = Request(
            f"{DRONE_API_URL.rstrip('/')}/telemetry",
            data=data,
            headers=headers,
        )
        with urlopen(req, timeout=5) as resp:
            resp.read()

    await asyncio.to_thread(_post)


async def _simulate_flight(req: StartRequest) -> None:
    start_time = time.time()

    try:
        while True:
            now = time.time()
            elapsed = now - start_time
            progress = min(1.0, elapsed / req.duration_sec) if req.duration_sec > 0 else 1.0
            delivered = progress >= 1.0

            lat = req.start_lat + (req.end_lat - req.start_lat) * progress
            lng = req.start_lng + (req.end_lng - req.start_lng) * progress

            telemetry = {
                "eventId": str(uuid.uuid4()),
                "orderId": req.orderId,
                "lat": lat,
                "lng": lng,
                "delivered": delivered,
                "progress": progress,
                "status": _build_status(progress, delivered),
                "timestamp": now,
            }

            await _send_telemetry(telemetry)

            if delivered:
                break

            await asyncio.sleep(req.update_interval_sec)
    except asyncio.CancelledError:
        pass
    except Exception as exc:
        print(f"Simulator error for {req.orderId}: {exc}")
    finally:
        active_flights.pop(req.orderId, None)


@app.post("/start")
async def start_simulation(req: StartRequest, _: None = Depends(_require_simulator_token)):
    existing = active_flights.get(req.orderId)
    if existing:
        existing.cancel()

    task = asyncio.create_task(_simulate_flight(req))
    active_flights[req.orderId] = task
    return {"status": "started", "orderId": req.orderId}


@app.get("/")
def root(_: None = Depends(_require_simulator_token)):
    return {"status": "ok"}
