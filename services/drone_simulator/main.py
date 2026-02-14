from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel
import asyncio
import json
import os
import time
import uuid
from urllib.request import Request, urlopen
import jwt
from pathlib import Path

TRACKING_URL = os.getenv("TRACKING_URL", "http://127.0.0.1:8002")
JWT_PRIVATE_KEY = os.getenv("JWT_PRIVATE_KEY")
JWT_PUBLIC_KEY = os.getenv("JWT_PUBLIC_KEY")
JWT_PRIVATE_KEY_PATH = os.getenv("JWT_PRIVATE_KEY_PATH")
JWT_PUBLIC_KEY_PATH = os.getenv("JWT_PUBLIC_KEY_PATH")
JWT_ISSUER = os.getenv("JWT_ISSUER", "droneapp")
JWT_AUDIENCE = os.getenv("JWT_AUDIENCE", "droneapp-clients")
ACCESS_TTL_SECONDS = int(os.getenv("ACCESS_TTL_SECONDS", "900"))

app = FastAPI(title="Drone Simulator")

active_flights: dict[str, asyncio.Task] = {}


class StartRequest(BaseModel):
    delivery_id: str
    start_lat: float = 43.238949
    start_lng: float = 76.889709
    end_lat: float = 43.2409
    end_lng: float = 76.9170
    duration_sec: float = 10.0
    update_interval_sec: float = 5.0


def _read_key_value(value: str | None, path: str | None, env_name: str) -> str:
    if value:
        return value.replace("\\n", "\n")
    if path:
        try:
            return Path(path).read_text(encoding="utf-8")
        except Exception as exc:
            raise RuntimeError(f"Failed to read {env_name} from {path}: {exc}")
    raise RuntimeError(f"{env_name} not configured")


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


def _decode_token(token: str) -> dict:
    return jwt.decode(
        token,
        _load_public_key(),
        algorithms=["RS256"],
        audience=JWT_AUDIENCE,
        issuer=JWT_ISSUER,
    )


def _extract_bearer(authorization: str | None) -> str | None:
    if not authorization:
        return None
    prefix = "bearer "
    if authorization.lower().startswith(prefix):
        return authorization[len(prefix):].strip()
    return None


def _require_simulator_token(authorization: str | None = Header(default=None)) -> dict:
    token = _extract_bearer(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Missing bearer token")
    try:
        claims = _decode_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")
    if claims.get("role") not in {"operator", "admin"}:
        raise HTTPException(status_code=403, detail="Insufficient role")
    return claims


def _build_status(progress: float, delivered: bool) -> str:
    if delivered:
        return "DELIVERED"
    if progress < 0.2:
        return "TAKING_OFF"
    if progress < 0.8:
        return "IN_FLIGHT"
    return "APPROACHING"


async def _send_telemetry(payload: dict) -> None:
    def _post() -> None:
        data = json.dumps(payload).encode("utf-8")
        token = _issue_access_token(payload["delivery_id"], "drone_device", ["telemetry:write"])
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        }
        req = Request(
            f"{TRACKING_URL.rstrip('/')}/telemetry",
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
                "delivery_id": req.delivery_id,
                "lat": lat,
                "lng": lng,
                "progress": progress,
                "status": _build_status(progress, delivered),
                "timestamp_utc": now,
            }

            await _send_telemetry(telemetry)

            if delivered:
                break

            await asyncio.sleep(req.update_interval_sec)
    except asyncio.CancelledError:
        pass
    except Exception as exc:
        print(f"Simulator error for {req.delivery_id}: {exc}")
    finally:
        active_flights.pop(req.delivery_id, None)


@app.post("/start")
async def start_simulation(req: StartRequest, _: dict = Depends(_require_simulator_token)):
    existing = active_flights.get(req.delivery_id)
    if existing:
        existing.cancel()

    task = asyncio.create_task(_simulate_flight(req))
    active_flights[req.delivery_id] = task
    return {"status": "started", "delivery_id": req.delivery_id}


@app.get("/")
def root():
    return {"status": "ok"}
