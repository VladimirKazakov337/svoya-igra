import json
import uuid
from typing import Dict, List, Optional
from fastapi import WebSocket
from datetime import datetime

class GameManager:
    def __init__(self):
        self.rooms: Dict = {}
        self.games: Dict = {}
        print("GameManager initialized")
    
    def create_room(self) -> str:
        """Create a new game room"""
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
        """Handle new player connection"""
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
        print(f"Players in room: {len(room['players'])}/5")
        await self.broadcast_room_state(room_code)
    
    async def disconnect(self, room_code: str, player_id: str):
        """Handle player disconnection"""
        if room_code in self.rooms:
            room = self.rooms[room_code]
            if player_id in room["players"]:
                player_name = room["players"][player_id]["name"]
                del room["players"][player_id]
                print(f"Player {player_name} disconnected from room {room_code}")
            
            # Clean up empty rooms
            if not room["players"]:
                print(f"Room {room_code} deleted (empty)")
                del self.rooms[room_code]
                if room_code in self.games:
                    del self.games[room_code]
            else:
                await self.broadcast_room_state(room_code)
    
    async def handle_message(self, room_code: str, player_id: str, message: dict):
        """Route messages to appropriate handlers"""
        if room_code not in self.rooms:
            return
        
        room = self.rooms[room_code]
        msg_type = message.get("type")
        
        print(f"Message from {player_id}: {msg_type}")
        
        handlers = {
            "join": self._handle_join,
            "set_creator": self._handle_set_creator,
            "start_game": self._handle_start_game,
            "select_question": self._handle_select_question,
            "open_question": self._handle_open_question,
            "answer_attempt": self._handle_answer_attempt,
            "evaluate_answer": self._handle_evaluate_answer,
            "skip_question": self._handle_skip_question,
            "final_bet": self._handle_final_bet,
            "final_answer": self._handle_final_answer,
            "evaluate_final": self._handle_evaluate_final,
            "eliminate_theme": self._handle_eliminate_theme,
            "save_game": self._handle_save_game,
            "ping": self._handle_ping,
        }
        
        handler = handlers.get(msg_type)
        if handler:
            await handler(room_code, player_id, message)
        else:
            print(f"Unknown message type: {msg_type}")
    
    # ============ ROOM HANDLERS ============
    
    async def _handle_join(self, room_code: str, player_id: str, message: dict):
        """Player joins with name"""
        room = self.rooms[room_code]
        player_name = message.get("name", "Player")
        room["players"][player_id]["name"] = player_name
        print(f"Player {player_id} set name: {player_name}")
        await self.broadcast_room_state(room_code)
    
    async def _handle_set_creator(self, room_code: str, player_id: str, message: dict):
        """Set room creator and host"""
        room = self.rooms[room_code]
        room["creator"] = player_id
        room["host"] = player_id
        room["players"][player_id]["is_host"] = True
        print(f"Player {player_id} is now host")
        await self.broadcast_room_state(room_code)
    
    async def _handle_start_game(self, room_code: str, player_id: str, message: dict):
        """Start the game (creator only)"""
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
        """Keep-alive ping"""
        await self.send_to_player(room_code, player_id, {"type": "pong"})
    
    # ============ GAME SETUP ============
    
    def _create_game(self) -> dict:
        """Create initial game state"""
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
    
    # ============ GAME MECHANICS ============
    
    async def _handle_select_question(self, room_code: str, player_id: str, message: dict):
        """Player selects a question from the board"""
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
        """Host opens question for answering"""
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        
        if not game or player_id != room["host"]:
            return
        
        if game["current_question"]:
            game["current_question"]["status"] = "open"
            
            # Enable answering for all players
            for pid in room["players"]:
                if pid != room["host"]:
                    room["players"][pid]["can_answer"] = True
            
            print("Question opened for answers")
            await self.broadcast_game_state(room_code)
    
    async def _handle_answer_attempt(self, room_code: str, player_id: str, message: dict):
        """Player attempts to answer"""
        game = self.games.get(room_code)
        room = self.rooms[room_code]
        
        if not game or not game["current_question"]:
            return
        
        if game["current_question"]["status"] != "open":
            return
        
        # First to press gets to answer
        if not game["answered_players"]:
            game["answered_players"].append(player_id)
            game["current_question"]["status"] = "answering"
            
            # Disable other players
            for pid in room["players"]:
                if pid != player_id:
                    room["players"][pid]["can_answer"] = False
            
            print(f"Player {player_id} is answering")
            await self.broadcast_game_state(room_code)
    
    async def _handle_evaluate_answer(self, room_code: str, player_id: str, message: dict):
        """Host evaluates answer (correct/incorrect)"""
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
                
                # Remove question from board
                key = f"{game['current_question']['category']}_{price}"
                current_round = game["rounds"][game["current_round"]]
                if key in current_round["questions"]:
                    del current_round["questions"][key]
                
                game["current_question"] = None
                game["answered_players"] = []
                
                print(f"Correct answer! Player {answering_player} +{price}")
                await self._check_round_complete(room_code)
            else:
                room["players"][answering_player]["score"] -= price
                game["current_question"]["status"] = "open"
                game["answered_players"] = []
                
                # Allow other players to try
                for pid in room["players"]:
                    if pid != room["host"] and pid != answering_player:
                        room["players"][pid]["can_answer"] = True
                
                print(f"Wrong answer! Player {answering_player} -{price}")
            
            await self.broadcast_game_state(room_code)
    
    async def _handle_skip_question(self, room_code: str, player_id: str, message: dict):
        """Host skips current question"""
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
        """Check if current round is complete"""
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
    
    # ============ FINAL ROUND ============
    
    async def _start_final_round(self, room_code: str):
        """Initialize final round"""
        game = self.games.get(room_code)
        room = self.rooms[room_code]
        
        game["phase"] = "final"
        
        # First eliminator: player with highest score
        players = [(pid, p["score"]) for pid, p in room["players"].items() if pid != room["host"]]
        if players:
            players.sort(key=lambda x: x[1], reverse=True)
            game["final_round"]["current_eliminator"] = players[0][0]
        
        print("Final round started!")
        await self.broadcast_game_state(room_code)
    
    async def _handle_eliminate_theme(self, room_code: str, player_id: str, message: dict):
        """Eliminate theme in final round"""
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
                # Final theme selected
                final_round["selected_theme"] = remaining[0]
                game["phase"] = "final_betting"
                print(f"Final theme: {remaining[0]}")
            else:
                # Next player eliminates
                players = [pid for pid in room["players"] if pid != room["host"]]
                current_idx = players.index(player_id)
                next_idx = (current_idx + 1) % len(players)
                final_round["current_eliminator"] = players[next_idx]
            
            await self.broadcast_game_state(room_code)
    
    async def _handle_final_bet(self, room_code: str, player_id: str, message: dict):
        """Player places final bet"""
        game = self.games.get(room_code)
        room = self.rooms[room_code]
        
        if not game or game["phase"] != "final_betting":
            return
        
        bet = message.get("bet", 0)
        current_score = room["players"][player_id]["score"]
        
        if 0 <= bet <= max(0, current_score):
            game["final_bets"][player_id] = bet
            print(f"Player {player_id} bet: {bet}")
            await self.broadcast_game_state(room_code)
    
    async def _handle_final_answer(self, room_code: str, player_id: str, message: dict):
        """Player submits final answer"""
        game = self.games.get(room_code)
        
        if not game or game["phase"] != "final_answering":
            return
        
        answer = message.get("answer", "")
        game["final_answers"][player_id] = answer
        print(f"Player {player_id} submitted final answer")
        await self.broadcast_game_state(room_code)
    
    async def _handle_evaluate_final(self, room_code: str, player_id: str, message: dict):
        """Host evaluates final answers"""
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
        print("Game finished!")
        await self.broadcast_game_state(room_code)
    
    async def _handle_save_game(self, room_code: str, player_id: str, message: dict):
        """Save game results (creator only)"""
        room = self.rooms[room_code]
        if player_id != room["creator"]:
            return
        
        # Here you would save to database/file
        await self.send_to_player(room_code, player_id, {
            "type": "game_saved",
            "message": "Game saved successfully"
        })
    
    # ============ BROADCAST METHODS ============
    
    async def broadcast_room_state(self, room_code: str):
        """Send room state to all players"""
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
        """Send game state to all players"""
        if room_code not in self.rooms:
            return
        
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        
        if not game:
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
        """Send message to specific player"""
        room = self.rooms.get(room_code)
        if room and player_id in room["players"]:
            try:
                await room["players"][player_id]["websocket"].send_json(message)
            except:
                await self.disconnect(room_code, player_id)
    
    def get_room_status(self, room_code: str) -> dict:
        """Get room information"""
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
