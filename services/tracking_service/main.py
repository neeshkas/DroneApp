from fastapi import FastAPI, HTTPException, Depends, Header, WebSocket, WebSocketException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import sqlite3
import time
from typing import Optional
from pathlib import Path
import json
import os
import asyncio
import jwt

DB_PATH = Path(__file__).parent / "tracking.db"
JWT_PUBLIC_KEY = os.getenv("JWT_PUBLIC_KEY")
JWT_PUBLIC_KEY_PATH = os.getenv("JWT_PUBLIC_KEY_PATH")
JWT_ISSUER = os.getenv("JWT_ISSUER", "droneapp")
JWT_AUDIENCE = os.getenv("JWT_AUDIENCE", "droneapp-clients")
CORS_ALLOW_ORIGINS = os.getenv("CORS_ALLOW_ORIGINS", "*")

app = FastAPI(title="Tracking Service")

allow_origins = [o.strip() for o in CORS_ALLOW_ORIGINS.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins if allow_origins else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)


class TelemetryIn(BaseModel):
    delivery_id: str
    lat: float
    lng: float
    progress: float
    status: str
    timestamp_utc: float


class TelemetryOut(BaseModel):
    delivery_id: str
    lat: float
    lng: float
    progress: float
    status: str
    timestamp_utc: float


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
        CREATE TABLE IF NOT EXISTS telemetry_events(
          event_id TEXT PRIMARY KEY,
          delivery_id TEXT,
          lat REAL,
          lng REAL,
          progress REAL,
          status TEXT,
          timestamp_utc REAL
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS delivery_state(
          delivery_id TEXT PRIMARY KEY,
          lat REAL,
          lng REAL,
          progress REAL,
          status TEXT,
          timestamp_utc REAL
        )
        """
    )
    cur.execute("CREATE INDEX IF NOT EXISTS idx_telemetry_delivery_id ON telemetry_events(delivery_id)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_telemetry_ts ON telemetry_events(timestamp_utc)")
    conn.commit()
    conn.close()


init_db()


def _load_public_key() -> str:
    if JWT_PUBLIC_KEY:
        return JWT_PUBLIC_KEY.replace("\\n", "\n")
    if JWT_PUBLIC_KEY_PATH:
        try:
            return Path(JWT_PUBLIC_KEY_PATH).read_text(encoding="utf-8")
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Failed to read JWT_PUBLIC_KEY from {JWT_PUBLIC_KEY_PATH}: {exc}")
    raise HTTPException(status_code=500, detail="JWT_PUBLIC_KEY not configured")


def _decode_token(token: str) -> dict:
    return jwt.decode(
        token,
        _load_public_key(),
        algorithms=["RS256"],
        audience=JWT_AUDIENCE,
        issuer=JWT_ISSUER,
    )


def _extract_bearer(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    prefix = "bearer "
    if authorization.lower().startswith(prefix):
        return authorization[len(prefix):].strip()
    return None


def require_auth(
    authorization: Optional[str] = Header(default=None),
    roles: Optional[list[str]] = None,
    scopes: Optional[list[str]] = None,
) -> dict:
    token = _extract_bearer(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Missing bearer token")
    try:
        claims = _decode_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

    if roles and claims.get("role") not in roles:
        raise HTTPException(status_code=403, detail="Insufficient role")
    if scopes:
        token_scopes = set(claims.get("scopes", []))
        if not set(scopes).issubset(token_scopes):
            raise HTTPException(status_code=403, detail="Missing scope")
    return claims


connected_clients: dict[str, set[WebSocket]] = {}
clients_lock = asyncio.Lock()


def _persist_telemetry(payload: TelemetryIn) -> None:
    conn = get_conn()
    try:
        cur = conn.cursor()
        event_id = f"{payload.delivery_id}-{payload.timestamp_utc}"
        cur.execute(
            """
            INSERT OR REPLACE INTO telemetry_events (event_id, delivery_id, lat, lng, progress, status, timestamp_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                event_id,
                payload.delivery_id,
                payload.lat,
                payload.lng,
                payload.progress,
                payload.status,
                payload.timestamp_utc,
            ),
        )
        cur.execute(
            """
            INSERT INTO delivery_state (delivery_id, lat, lng, progress, status, timestamp_utc)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(delivery_id) DO UPDATE SET
              lat = excluded.lat,
              lng = excluded.lng,
              progress = excluded.progress,
              status = excluded.status,
              timestamp_utc = excluded.timestamp_utc
            """,
            (
                payload.delivery_id,
                payload.lat,
                payload.lng,
                payload.progress,
                payload.status,
                payload.timestamp_utc,
            ),
        )
        conn.commit()
    finally:
        conn.close()


def _get_state(delivery_id: str) -> Optional[TelemetryOut]:
    conn = get_conn()
    try:
        row = conn.cursor().execute(
            "SELECT delivery_id, lat, lng, progress, status, timestamp_utc FROM delivery_state WHERE delivery_id = ?",
            (delivery_id,),
        ).fetchone()
        if not row:
            return None
        return TelemetryOut(**dict(row))
    finally:
        conn.close()


async def _broadcast(delivery_id: str, payload: dict) -> None:
    async with clients_lock:
        targets = list(connected_clients.get(delivery_id, set()))
    if not targets:
        return

    message = json.dumps(payload)
    dead = []
    for ws in targets:
        try:
            await ws.send_text(message)
        except Exception:
            dead.append(ws)

    if dead:
        async with clients_lock:
            for ws in dead:
                connected_clients.get(delivery_id, set()).discard(ws)


@app.post("/telemetry")
async def ingest_telemetry(payload: TelemetryIn, _: dict = Depends(lambda authorization=Header(default=None): require_auth(authorization, roles=["drone_device"]))):
    _persist_telemetry(payload)
    await _broadcast(payload.delivery_id, payload.model_dump())
    return {"status": "ok"}


@app.get("/track/{delivery_id}", response_model=TelemetryOut)
def get_tracking(delivery_id: str, claims: dict = Depends(lambda authorization=Header(default=None): require_auth(authorization, scopes=["tracking:read"]))):
    if claims.get("sub") != delivery_id:
        raise HTTPException(status_code=403, detail="Invalid delivery scope")
    state = _get_state(delivery_id)
    if not state:
        raise HTTPException(status_code=404, detail="No telemetry")
    return state


@app.websocket("/ws/track/{delivery_id}")
async def websocket_track(websocket: WebSocket, delivery_id: str):
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4401)
        return
    try:
        claims = _decode_token(token)
    except Exception:
        await websocket.close(code=4401)
        return
    if claims.get("sub") != delivery_id or "tracking:read" not in set(claims.get("scopes", [])):
        await websocket.close(code=4403)
        return

    await websocket.accept()
    async with clients_lock:
        connected_clients.setdefault(delivery_id, set()).add(websocket)

    state = _get_state(delivery_id)
    if state:
        await websocket.send_text(json.dumps(state.model_dump()))

    try:
        while True:
            await websocket.receive_text()
    except Exception:
        pass
    finally:
        async with clients_lock:
            connected_clients.get(delivery_id, set()).discard(websocket)


@app.get("/")
def root():
    return {"status": "ok"}
