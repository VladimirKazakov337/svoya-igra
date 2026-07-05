import asyncio
import websockets
import json
import uuid
import requests

async def recv_json(ws):
    """Receive and parse JSON message"""
    msg = await ws.recv()
    return json.loads(msg)

async def test_full_game():
    print("=" * 60)
    print("FULL GAME TEST")
    print("=" * 60)
    
    # Create room
    r = requests.post("http://localhost:8000/api/create_room")
    room_code = r.json()["room_code"]
    print(f"\nRoom: {room_code}")
    
    host_id = str(uuid.uuid4())[:8]
    player1_id = str(uuid.uuid4())[:8]
    
    try:
        # Connect host
        print("Connecting host...")
        async with websockets.connect(
            f"ws://localhost:8000/ws/{room_code}/{host_id}"
        ) as host_ws:
            # Host joins
            await host_ws.send(json.dumps({"type": "join", "name": "Host"}))
            resp = await recv_json(host_ws)
            print(f"Host joined. Players: {resp['players_count']}")
            
            # Set creator
            await host_ws.send(json.dumps({"type": "set_creator"}))
            resp = await recv_json(host_ws)
            print(f"Host is creator: {resp['creator'] == host_id}")
            
            # Connect player 1
            print("Connecting player...")
            async with websockets.connect(
                f"ws://localhost:8000/ws/{room_code}/{player1_id}"
            ) as p1_ws:
                await p1_ws.send(json.dumps({"type": "join", "name": "Player 1"}))
                
                # Both get room state updates
                host_resp = await recv_json(host_ws)
                p1_resp = await recv_json(p1_ws)
                print(f"Players in room: {p1_resp['players_count']}")
                
                # START GAME
                print("\nStarting game...")
                await host_ws.send(json.dumps({"type": "start_game"}))
                
                # Wait for game_state from both
                host_msg = await recv_json(host_ws)
                p1_msg = await recv_json(p1_ws)
                
                print(f"Host got: {host_msg['type']}")
                print(f"P1 got: {p1_msg['type']}")
                
                if host_msg['type'] != 'game_state':
                    print(f"FAIL: Expected game_state, got {host_msg['type']}")
                    return
                
                game = host_msg['game']
                print(f"Phase: {game['phase']}")
                print(f"Round: {game['rounds'][game['current_round']]['name']}")
                
                # SELECT QUESTION
                print("\nSelecting question...")
                await p1_ws.send(json.dumps({
                    "type": "select_question",
                    "category": "Theme 1",
                    "price": 100
                }))
                
                host_msg = await recv_json(host_ws)
                p1_msg = await recv_json(p1_ws)
                
                q = host_msg['game']['current_question']
                print(f"Question: {q['category']} - {q['price']}")
                print(f"Status: {q['status']}")
                
                # OPEN QUESTION
                print("\nOpening question...")
                await host_ws.send(json.dumps({"type": "open_question"}))
                
                host_msg = await recv_json(host_ws)
                p1_msg = await recv_json(p1_ws)
                
                print(f"Status: {host_msg['game']['current_question']['status']}")
                print(f"P1 can answer: {p1_msg['players'][player1_id]['can_answer']}")
                
                # ANSWER
                print("\nPlayer answering...")
                await p1_ws.send(json.dumps({"type": "answer_attempt"}))
                
                host_msg = await recv_json(host_ws)
                p1_msg = await recv_json(p1_ws)
                
                print(f"Status: {host_msg['game']['current_question']['status']}")
                
                # EVALUATE AS CORRECT
                print("\nEvaluating as CORRECT...")
                await host_ws.send(json.dumps({
                    "type": "evaluate_answer",
                    "correct": True
                }))
                
                host_msg = await recv_json(host_ws)
                p1_msg = await recv_json(p1_ws)
                
                score = p1_msg['players'][player1_id]['score']
                print(f"\nPlayer 1 score: {score}")
                
                print("\n" + "=" * 60)
                if score == 100:
                    print("GAME TEST PASSED!")
                else:
                    print(f"Expected score 100, got {score}")
                print("=" * 60)
                
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_full_game())
