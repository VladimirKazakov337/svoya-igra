from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import json
import uvicorn
from game_manager import GameManager

app = FastAPI(title="Своя Игра API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

game_manager = GameManager()

@app.get("/")
async def root():
    return {"message": "Своя Игра Server is running", "status": "ok"}

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/api/create_room")
async def create_room():
    room_code = game_manager.create_room()
    return {"room_code": room_code, "status": "created"}

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
        print(f"Error in websocket: {e}")
        await game_manager.disconnect(room_code, player_id)

if __name__ == "__main__":
    print("🚀 Запуск сервера Своей Игры...")
    print("📡 Сервер доступен по адресу: http://localhost:8000")
    print("📚 Документация API: http://localhost:8000/docs")
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
