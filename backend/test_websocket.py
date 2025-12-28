#!/usr/bin/env python
"""
Simple WebSocket client to test the drone delivery tracking system.
Usage: python test_websocket.py
"""

import asyncio
import json
import websockets


async def test_websocket():
    uri = "ws://127.0.0.1:8000/ws/drone"

    async with websockets.connect(uri) as websocket:
        print(f"Connected to {uri}")

        message = {
            "type": "start_tracking",
            "orderId": "TEST-ORDER-001",
            "start_lat": 43.235,
            "start_lng": 76.88,
            "end_lat": 43.24,
            "end_lng": 76.90,
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
