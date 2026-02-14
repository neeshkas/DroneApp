# DroneApp

Demo drone food delivery with independent services (Docker-first).

## Architecture

One-way REST calls:

- Order API -> Drone Simulator: `POST /start`
- Drone Simulator -> Tracking Service: `POST /telemetry`
- Frontend -> Order API: `POST /deliveries`
- Frontend -> Tracking Service: `GET /track/{delivery_id}` and WS `/ws/track/{delivery_id}`

Services:
- **Order API** — orders, stores/products, launch simulation, issue tracking tokens.
- **Tracking Service** — store/serve coordinates, WebSocket for frontend.
- **Drone Simulator** — simulates flight and sends telemetry.
- **Frontend (Flutter Web)** — UI, runs via Docker (nginx).

## Quick start (Docker only)

```powershell
docker compose up -d --build
```

After start:
- Frontend: `http://127.0.0.1:18080`
- Order API: `http://127.0.0.1:18000`
- Drone Simulator: `http://127.0.0.1:18001`
- Tracking Service: `http://127.0.0.1:18002`

## Main endpoints

Order API (18000):
- `POST /deliveries` — create delivery and start simulation, return tracking tokens.
- `GET /stores` — stores list.
- `GET /products` — products list.
- `GET /geocode` / `GET /reverse-geocode` — address lookup.

Tracking Service (18002):
- `POST /telemetry` — telemetry (drone_device only).
- `GET /track/{delivery_id}` — current position (JWT access).
- `WS /ws/track/{delivery_id}?token=...` — realtime tracking.

## Docs

- `TECHNICAL_SPECIFICATION.md` — technical specification
- `docs/things_to_fix.md` — list of critical improvements
