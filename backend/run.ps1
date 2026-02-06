$env:DRONE_API_TOKEN='test-token'
$env:DRONE_ORDER_TOKEN_SECRET='a-secret'
$env:DRONE_SIMULATOR_TOKEN='test-token'
.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000