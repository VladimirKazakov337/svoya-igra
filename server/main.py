from fastapi import FastAPI, WebSocket, WebSocketDisconnect, UploadFile, File
from fastapi.staticfiles import StaticFiles
from pathlib import Path
import os
import shutil
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
import json
import uuid
import os
import uvicorn
from game_manager import GameManager

game_manager = GameManager()
# Create uploads directory
UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "..", "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

app = FastAPI(title="Svoya Igra API")
BASE_DIR = Path(__file__).resolve().parent.parent
ASSETS_DIR = BASE_DIR / "web" / "assets"

app.mount("/web/assets", StaticFiles(directory=ASSETS_DIR), name="assets")

# Serve uploaded files
@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    filename = f"{uuid.uuid4().hex}_{file.filename}"
    filepath = os.path.join(UPLOAD_DIR, filename)
    with open(filepath, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"url": f"/uploads/{filename}"}
# Mount uploads directory
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

@app.get("/player.html")
async def player_page():
    html_path = os.path.join(os.path.dirname(__file__), "..", "web", "player.html")
    if os.path.exists(html_path):
        with open(html_path, "r", encoding="utf-8") as f:
            return HTMLResponse(content=f.read())
    return HTMLResponse(content="<h1>Player page not found</h1>")

@app.get("/")
async def root():
    html_path = os.path.join(os.path.dirname(__file__), "..", "web", "index.html")
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

@app.get("/api/template")
async def get_template():
    return game_manager.create_template()

@app.post("/api/save_template/{room_code}")
async def save_template(room_code: str, template: dict):
    if game_manager.save_template(room_code, template):
        return {"status": "ok"}
    return {"status": "error", "message": "Room not found"}

@app.post("/api/draft/save")
async def save_draft(data: dict):
    draft_id = data.get("id", str(uuid.uuid4())[:8])
    template = data.get("template")
    game_manager.save_draft(draft_id, template)
    return {"draft_id": draft_id, "status": "saved"}

@app.post("/api/draft/load")
async def load_draft(data: dict):
    draft_id = data.get("id")
    template = game_manager.load_draft(draft_id)
    if template:
        return {"template": template, "status": "ok"}
    return {"status": "error", "message": "Draft not found"}

@app.get("/api/drafts")
async def list_drafts():
    return {"drafts": game_manager.list_drafts()}

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