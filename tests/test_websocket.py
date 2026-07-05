import asyncio
import websockets
import json
import uuid

async def test():
    player_id = str(uuid.uuid4())[:8]
    uri = f"ws://localhost:8000/ws/TEST01/{player_id}"
    
    print(f"Connecting to {uri}")
    
    async with websockets.connect(uri) as ws:
        # Join
        await ws.send(json.dumps({"type": "join", "name": "Test Player"}))
        response = await ws.recv()
        print(f"Room state: {json.loads(response)}")
        
        # Ping
        await ws.send(json.dumps({"type": "ping"}))
        pong = await ws.recv()
        print(f"Pong: {pong}")
        
        print("WebSocket test successful!")

asyncio.run(test())
