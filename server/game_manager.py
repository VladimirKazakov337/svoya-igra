import json
import uuid
from typing import Dict
from fastapi import WebSocket
from datetime import datetime

class GameManager:
    def __init__(self):
        self.rooms: Dict = {}
        self.games: Dict = {}
        print("GameManager initialized")
    
    def create_room(self) -> str:
        room_code = str(uuid.uuid4())[:6].upper()
        self.rooms[room_code] = {
            "players": {},
            "creator": None,
            "host": None,
            "status": "waiting",
            "game_state": None,
            "created_at": datetime.now().isoformat()
        }
        print(f"Room created: {room_code}")
        return room_code
    
    async def connect(self, room_code: str, player_id: str, websocket: WebSocket):
        if room_code not in self.rooms:
            await websocket.close(code=4004, reason="Room not found")
            return
        
        room = self.rooms[room_code]
        
        if len(room["players"]) >= 5:
            await websocket.send_json({
                "type": "error",
                "message": "Room is full (max 5 players)"
            })
            await websocket.close(code=4000, reason="Room full")
            return
        
        room["players"][player_id] = {
            "websocket": websocket,
            "name": f"Player {len(room['players']) + 1}",
            "score": 0,
            "is_host": False,
            "can_answer": False,
            "connected": True
        }
        
        print(f"Player {player_id} connected to room {room_code}")
        await self.broadcast_room_state(room_code)
    
    async def disconnect(self, room_code: str, player_id: str):
        if room_code in self.rooms:
            room = self.rooms[room_code]
            if player_id in room["players"]:
                player_name = room["players"][player_id]["name"]
                del room["players"][player_id]
                print(f"Player {player_name} disconnected")
            
            if not room["players"]:
                print(f"Room {room_code} deleted")
                del self.rooms[room_code]
                if room_code in self.games:
                    del self.games[room_code]
            else:
                await self.broadcast_room_state(room_code)
    
    async def handle_message(self, room_code: str, player_id: str, message: dict):
        if room_code not in self.rooms:
            return
        
        msg_type = message.get("type")
        print(f"Message from {player_id}: {msg_type}")
        
        if msg_type == "join":
            await self._handle_join(room_code, player_id, message)
        elif msg_type == "set_creator":
            await self._handle_set_creator(room_code, player_id, message)
        elif msg_type == "start_game":
            await self._handle_start_game(room_code, player_id, message)
        elif msg_type == "select_question":
            await self._handle_select_question(room_code, player_id, message)
        elif msg_type == "open_question":
            await self._handle_open_question(room_code, player_id, message)
        elif msg_type == "answer_attempt":
            await self._handle_answer_attempt(room_code, player_id, message)
        elif msg_type == "evaluate_answer":
            await self._handle_evaluate_answer(room_code, player_id, message)
        elif msg_type == "skip_question":
            await self._handle_skip_question(room_code, player_id, message)
        elif msg_type == "final_bet":
            await self._handle_final_bet(room_code, player_id, message)
        elif msg_type == "final_answer":
            await self._handle_final_answer(room_code, player_id, message)
        elif msg_type == "evaluate_final":
            await self._handle_evaluate_final(room_code, player_id, message)
        elif msg_type == "eliminate_theme":
            await self._handle_eliminate_theme(room_code, player_id, message)
        elif msg_type == "save_game":
            await self._handle_save_game(room_code, player_id, message)
        elif msg_type == "ping":
            await self._handle_ping(room_code, player_id, message)
    
    async def _handle_join(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        player_name = message.get("name", "Player")
        room["players"][player_id]["name"] = player_name
        await self.broadcast_room_state(room_code)
    
    async def _handle_set_creator(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        room["creator"] = player_id
        room["host"] = player_id
        room["players"][player_id]["is_host"] = True
        print(f"Player {player_id} is now host")
        await self.broadcast_room_state(room_code)
    
    async def _handle_start_game(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        if room["creator"] != player_id:
            return
        
        game = self._create_game()
        self.games[room_code] = game
        room["status"] = "playing"
        room["game_state"] = game
        print(f"Game started in room {room_code}")
        await self.broadcast_game_state(room_code)
    
    async def _handle_ping(self, room_code: str, player_id: str, message: dict):
        await self.send_to_player(room_code, player_id, {"type": "pong"})
    
    def _create_game(self) -> dict:
        rounds_config = [
            {"name": "Round 1", "prices": [100, 200, 300, 400, 500]},
            {"name": "Round 2", "prices": [200, 400, 600, 800, 1000]},
            {"name": "Round 3", "prices": [300, 600, 900, 1200, 1500]},
        ]
        
        rounds = []
        for config in rounds_config:
            questions = {}
            for i in range(5):
                for price in config["prices"]:
                    key = f"Theme_{i+1}_{price}"
                    questions[key] = {
                        "text": f"Question for {price} points",
                        "answer": f"Answer {i+1}",
                        "category": f"Theme {i+1}",
                        "price": price
                    }
            
            rounds.append({
                "name": config["name"],
                "prices": config["prices"],
                "categories": [f"Theme {i}" for i in range(1, 6)],
                "questions": questions
            })
        
        return {
            "current_round": 0,
            "current_question": None,
            "answered_players": [],
            "last_correct_player": None,
            "phase": "playing",
            "final_bets": {},
            "final_answers": {},
            "rounds": rounds,
            "final_round": {
                "themes": [f"Final Theme {i}" for i in range(1, 11)],
                "questions": {},
                "selected_theme": None,
                "eliminated_themes": [],
                "current_eliminator": None
            }
        }
    
    async def _handle_select_question(self, room_code: str, player_id: str, message: dict):
        game = self.games.get(room_code)
        if not game or game["phase"] != "playing":
            return
        
        category = message.get("category")
        price = message.get("price")
        question_key = f"{category}_{price}"
        
        current_round = game["rounds"][game["current_round"]]
        question = current_round["questions"].get(question_key)
        
        if question:
            game["current_question"] = {
                "category": category,
                "price": price,
                "selected_by": player_id,
                "question": question,
                "status": "selected"
            }
            print(f"Question selected: {category} - {price}")
            await self.broadcast_game_state(room_code)
    
    async def _handle_open_question(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        
        if not game or player_id != room["host"]:
            return
        
        if game["current_question"]:
            game["current_question"]["status"] = "open"
            for pid in room["players"]:
                if pid != room["host"]:
                    room["players"][pid]["can_answer"] = True
            print("Question opened")
            await self.broadcast_game_state(room_code)
    
    async def _handle_answer_attempt(self, room_code: str, player_id: str, message: dict):
        game = self.games.get(room_code)
        room = self.rooms[room_code]
        
        if not game or not game["current_question"]:
            return
        if game["current_question"]["status"] != "open":
            return
        
        if not game["answered_players"]:
            game["answered_players"].append(player_id)
            game["current_question"]["status"] = "answering"
            for pid in room["players"]:
                if pid != player_id:
                    room["players"][pid]["can_answer"] = False
            print(f"Player {player_id} is answering")
            await self.broadcast_game_state(room_code)
    
    async def _handle_evaluate_answer(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        
        if not game or player_id != room["host"]:
            return
        
        is_correct = message.get("correct", False)
        answering_player = game["answered_players"][-1] if game["answered_players"] else None
        
        if answering_player:
            price = game["current_question"]["price"]
            
            if is_correct:
                room["players"][answering_player]["score"] += price
                game["last_correct_player"] = answering_player
                
                key = f"{game['current_question']['category']}_{price}"
                current_round = game["rounds"][game["current_round"]]
                if key in current_round["questions"]:
                    del current_round["questions"][key]
                
                game["current_question"] = None
                game["answered_players"] = []
                print(f"Correct! Player +{price}")
                await self._check_round_complete(room_code)
            else:
                room["players"][answering_player]["score"] -= price
                game["current_question"]["status"] = "open"
                game["answered_players"] = []
                
                for pid in room["players"]:
                    if pid != room["host"] and pid != answering_player:
                        room["players"][pid]["can_answer"] = True
                print(f"Wrong! Player -{price}")
            
            await self.broadcast_game_state(room_code)
    
    async def _handle_skip_question(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        
        if not game or player_id != room["host"]:
            return
        
        if game["current_question"]:
            key = f"{game['current_question']['category']}_{game['current_question']['price']}"
            current_round = game["rounds"][game["current_round"]]
            if key in current_round["questions"]:
                del current_round["questions"][key]
            
            game["current_question"] = None
            game["answered_players"] = []
            print("Question skipped")
            await self._check_round_complete(room_code)
            await self.broadcast_game_state(room_code)
    
    async def _check_round_complete(self, room_code: str):
        game = self.games.get(room_code)
        if not game:
            return
        
        current_round = game["rounds"][game["current_round"]]
        
        if not current_round["questions"]:
            if game["current_round"] < 2:
                game["current_round"] += 1
                game["current_question"] = None
                print(f"Moving to round {game['current_round'] + 1}")
                await self.broadcast_game_state(room_code)
            else:
                await self._start_final_round(room_code)
    
    async def _start_final_round(self, room_code: str):
        game = self.games.get(room_code)
        room = self.rooms[room_code]
        
        game["phase"] = "final"
        
        players = [(pid, p["score"]) for pid, p in room["players"].items() if pid != room["host"]]
        if players:
            players.sort(key=lambda x: x[1], reverse=True)
            game["final_round"]["current_eliminator"] = players[0][0]
        
        print("Final round started!")
        await self.broadcast_game_state(room_code)
    
    async def _handle_eliminate_theme(self, room_code: str, player_id: str, message: dict):
        game = self.games.get(room_code)
        room = self.rooms[room_code]
        
        if not game or game["phase"] != "final":
            return
        
        final_round = game["final_round"]
        
        if player_id != final_round["current_eliminator"]:
            return
        
        theme = message.get("theme")
        if theme and theme in final_round["themes"] and theme not in final_round["eliminated_themes"]:
            final_round["eliminated_themes"].append(theme)
            
            remaining = [t for t in final_round["themes"] if t not in final_round["eliminated_themes"]]
            
            if len(remaining) == 1:
                final_round["selected_theme"] = remaining[0]
                game["phase"] = "final_betting"
            else:
                players = [pid for pid in room["players"] if pid != room["host"]]
                current_idx = players.index(player_id)
                next_idx = (current_idx + 1) % len(players)
                final_round["current_eliminator"] = players[next_idx]
            
            await self.broadcast_game_state(room_code)
    
    async def _handle_final_bet(self, room_code: str, player_id: str, message: dict):
        game = self.games.get(room_code)
        room = self.rooms[room_code]
        
        if not game or game["phase"] != "final_betting":
            return
        
        bet = message.get("bet", 0)
        current_score = room["players"][player_id]["score"]
        
        if 0 <= bet <= max(0, current_score):
            game["final_bets"][player_id] = bet
            await self.broadcast_game_state(room_code)
    
    async def _handle_final_answer(self, room_code: str, player_id: str, message: dict):
        game = self.games.get(room_code)
        
        if not game or game["phase"] != "final_answering":
            return
        
        game["final_answers"][player_id] = message.get("answer", "")
        await self.broadcast_game_state(room_code)
    
    async def _handle_evaluate_final(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        
        if not game or player_id != room["host"]:
            return
        
        results = message.get("results", {})
        
        for pid, correct in results.items():
            bet = game["final_bets"].get(pid, 0)
            if correct:
                room["players"][pid]["score"] += bet
            else:
                room["players"][pid]["score"] -= bet
        
        game["phase"] = "finished"
        room["status"] = "finished"
        await self.broadcast_game_state(room_code)
    
    async def _handle_save_game(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        if player_id != room["creator"]:
            return
        
        await self.send_to_player(room_code, player_id, {
            "type": "game_saved",
            "message": "Game saved successfully"
        })
    
    async def broadcast_room_state(self, room_code: str):
        if room_code not in self.rooms:
            return
        
        room = self.rooms[room_code]
        players_info = {}
        
        for pid, player in room["players"].items():
            players_info[pid] = {
                "name": player["name"],
                "score": player["score"],
                "is_host": player["is_host"]
            }
        
        state = {
            "type": "room_state",
            "status": room["status"],
            "players": players_info,
            "players_count": len(players_info),
            "max_players": 5,
            "creator": room["creator"],
            "host": room["host"]
        }
        
        disconnected = []
        for pid, player in room["players"].items():
            try:
                await player["websocket"].send_json(state)
            except:
                disconnected.append(pid)
        
        for pid in disconnected:
            await self.disconnect(room_code, pid)
    
    async def broadcast_game_state(self, room_code: str):
        print(f'DEBUG broadcast: room={room_code}, games={list(self.games.keys())}')
        if room_code not in self.rooms:
            return
        
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        print(f'DEBUG: game={game is not None}')
        
        if not game:
            print('DEBUG: no game, sending room_state')
            await self.broadcast_room_state(room_code)
            return
        
        players_info = {}
        for pid, player in room["players"].items():
            players_info[pid] = {
                "name": player["name"],
                "score": player["score"],
                "can_answer": player.get("can_answer", False),
                "is_host": player["is_host"]
            }
        
        disconnected = []
        for pid, player in room["players"].items():
            try:
                state = {
                    "type": "game_state",
                    "game": game,
                    "players": players_info,
                    "current_player": pid,
                    "is_host": player["is_host"]
                }
                await player["websocket"].send_json(state)
            except:
                disconnected.append(pid)
        
        for pid in disconnected:
            await self.disconnect(room_code, pid)
    
    async def send_to_player(self, room_code: str, player_id: str, message: dict):
        room = self.rooms.get(room_code)
        if room and player_id in room["players"]:
            try:
                await room["players"][player_id]["websocket"].send_json(message)
            except:
                await self.disconnect(room_code, player_id)
    
    def get_room_status(self, room_code: str) -> dict:
        if room_code not in self.rooms:
            return {"error": "Room not found", "exists": False}
        
        room = self.rooms[room_code]
        return {
            "exists": True,
            "status": room["status"],
            "players_count": len(room["players"]),
            "max_players": 5,
            "created_at": room["created_at"]
        }
