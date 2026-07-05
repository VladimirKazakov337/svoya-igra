from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
import json
import os
import uvicorn
from game_manager import GameManager

game_manager = GameManager()
app = FastAPI(title="Svoya Igra API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

@app.get("/")
async def root():
    html_path = os.path.join(os.path.dirname(__file__), "..", "client", "web", "index.html")
    if os.path.exists(html_path):
        with open(html_path, "r", encoding="utf-8") as f:
            return HTMLResponse(content=f.read())
    return {"message": "Svoya Igra Server"}

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/api/create_room")
async def create_room():
    return {"room_code": game_manager.create_room(), "status": "created"}

@app.get("/api/room/{room_code}")
async def get_room_info(room_code: str):
    return game_manager.get_room_status(room_code)

@app.websocket("/ws/{room_code}/{player_id}")
async def websocket_endpoint(websocket: WebSocket, room_code: str, player_id: str):
    await websocket.accept()
    await game_manager.connect(room_code, player_id, websocket)
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            await game_manager.handle_message(room_code, player_id, message)
    except WebSocketDisconnect:
        await game_manager.disconnect(room_code, player_id)
    except Exception as e:
        print(f"Error: {e}")
        await game_manager.disconnect(room_code, player_id)

if __name__ == "__main__":
    print("Server: http://localhost:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=False)