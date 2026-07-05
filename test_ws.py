
import asyncio
import websockets
import json
import uuid

async def test():
    player_id = str(uuid.uuid4())[:8]
    room_code = "TEST01"
    
    uri = f"ws://localhost:8000/ws/{room_code}/{player_id}"
    
    print(f"Connecting to {uri}")
    
    try:
        async with websockets.connect(uri) as ws:
            # Join room
            await ws.send(json.dumps({
                "type": "join",
                "name": f"Player_{player_id}"
            }))
            print("Sent: join message")
            
            # Get response
            response = await ws.recv()
            data = json.loads(response)
            print("Received room state:")
            print(json.dumps(data, indent=2, ensure_ascii=False))
            
            # Send ping
            await ws.send(json.dumps({"type": "ping"}))
            pong = await ws.recv()
            print(f"Pong received: {pong}")
            
            print("\nTest SUCCESSFUL!")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    asyncio.run(test())
