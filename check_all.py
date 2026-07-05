
import requests
import asyncio
import websockets
import json
import uuid
import webbrowser
import sys

def check_http():
    print("=" * 60)
    print("HTTP TESTS")
    print("=" * 60)
    
    base_url = "http://localhost:8000"
    
    # Health
    try:
        r = requests.get(f"{base_url}/health")
        print(f"[OK] Health: {r.json()}")
    except Exception as e:
        print(f"[FAIL] Health: {e}")
        return False
    
    # Create room
    try:
        r = requests.post(f"{base_url}/api/create_room")
        data = r.json()
        print(f"[OK] Room created: {data.get('room_code')}")
        return data.get('room_code')
    except Exception as e:
        print(f"[FAIL] Create room: {e}")
        return False

async def check_websocket():
    print("\n" + "=" * 60)
    print("WEBSOCKET TEST")
    print("=" * 60)
    
    player_id = str(uuid.uuid4())[:8]
    uri = f"ws://localhost:8000/ws/TEST01/{player_id}"
    
    try:
        async with websockets.connect(uri) as ws:
            await ws.send(json.dumps({
                "type": "join",
                "name": f"Player_{player_id}"
            }))
            
            response = await ws.recv()
            data = json.loads(response)
            print(f"[OK] WebSocket connected")
            print(f"     Players in room: {data.get('players_count', 0)}")
            return True
    except Exception as e:
        print(f"[FAIL] WebSocket: {e}")
        return False

async def main():
    print("\n" + "=" * 60)
    print("SVOYA IGRA - SERVER CHECK")
    print("=" * 60)
    
    # HTTP tests
    room = check_http()
    
    # WebSocket test
    ws_ok = await check_websocket()
    
    print("\n" + "=" * 60)
    if room and ws_ok:
        print("ALL TESTS PASSED!")
        print("=" * 60)
        print(f"\nServer is running at: http://localhost:8000")
        print(f"API docs at: http://localhost:8000/docs")
        
        # Open browser
        try:
            webbrowser.open("http://localhost:8000/docs")
            print("Browser opened with API docs")
        except:
            print("Open http://localhost:8000/docs in your browser")
    else:
        print("SOME TESTS FAILED!")
        print("=" * 60)
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
