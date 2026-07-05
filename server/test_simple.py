from fastapi import FastAPI, WebSocket
import json
import uvicorn

app = FastAPI()

@app.websocket("/ws/test")
async def websocket_test(websocket: WebSocket):
    await websocket.accept()
    print("Client connected")
    
    # Receive message
    data = await websocket.receive_text()
    msg = json.loads(data)
    print(f"Received: {msg}")
    
    # Send game_state
    if msg.get("type") == "start":
        response = {
            "type": "game_state",
            "game": {"phase": "playing", "round": 1},
            "players": {"p1": {"name": "Test", "score": 0}}
        }
        await websocket.send_json(response)
        print("Sent game_state")
    else:
        response = {"type": "room_state", "status": "waiting"}
        await websocket.send_json(response)
        print("Sent room_state")
    
    await websocket.close()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
