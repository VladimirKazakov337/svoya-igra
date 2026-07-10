import json
import uuid
import random
from typing import Dict
from fastapi import WebSocket
from datetime import datetime

class GameManager:
    def __init__(self):
        self.rooms: Dict = {}
        self.games: Dict = {}
        print("GameManager initialized")

    def create_template(self) -> dict:
        rounds_config = [
            {"name": "Round 1", "prices": [100, 200, 300, 400, 500]},
            {"name": "Round 2", "prices": [200, 400, 600, 800, 1000]},
            {"name": "Round 3", "prices": [300, 600, 900, 1200, 1500]},
        ]
        rounds = []
        for rc in rounds_config:
            cats = []
            for i in range(5):
                questions = []
                for price in rc["prices"]:
                    questions.append({"price": price, "text": "", "answer": ""})
                cats.append({"name": f"Theme {i+1}", "questions": questions})
            rounds.append({"name": rc["name"], "categories": cats})
        final = [{"name": f"Theme {i+1}", "text": "", "answer": ""} for i in range(10)]
        return {"rounds": rounds, "final": final}

    def save_template(self, room_code: str, template: dict):
        if room_code in self.rooms:
            self.rooms[room_code]["template"] = template
            return True
        return False

    def get_template(self, room_code: str):
        if room_code in self.rooms:
            return self.rooms[room_code].get("template")
        return None

    def save_draft(self, draft_id: str, template: dict):
        import os
        draft_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "drafts")
        os.makedirs(draft_dir, exist_ok=True)
        filepath = os.path.join(draft_dir, f"{draft_id}.json")
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(template, f, ensure_ascii=False, indent=2)
        return True

    def load_draft(self, draft_id: str):
        import os
        draft_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "drafts")
        filepath = os.path.join(draft_dir, f"{draft_id}.json")
        if os.path.exists(filepath):
            with open(filepath, "r", encoding="utf-8") as f:
                return json.load(f)
        return None

    def list_drafts(self):
        import os
        draft_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "drafts")
        if not os.path.exists(draft_dir):
            return []
        drafts = []
        for filename in os.listdir(draft_dir):
            if filename.endswith(".json"):
                filepath = os.path.join(draft_dir, filename)
                mtime = os.path.getmtime(filepath)
                draft_id = filename.replace(".json", "")
                try:
                    with open(filepath, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    name = data.get("name", draft_id)
                except:
                    name = draft_id
                drafts.append({"id": draft_id, "name": name, "updated": mtime})
        drafts.sort(key=lambda x: x["updated"], reverse=True)
        return drafts

    def create_room(self) -> str:
        room_code = str(uuid.uuid4())[:6].upper()
        self.rooms[room_code] = {
            "players": {},
            "creator": None,
            "host": None,
            "host_name": "",
            "status": "waiting",
            "game_state": None,
            "template": None,
            "created_at": datetime.now().isoformat()
        }
        print(f"Room created: {room_code}")
        return room_code

    async def _skip_question(self, room_code, player_id, message):
        game = self.games.get(room_code)
        if not game or not game["current_question"]:
            return
        price = game["current_question"]["price"]
        key = f"{game['current_question']['category']}_{price}"
        current = game["rounds"][game["current_round"]]
        if key in current["questions"]:
            del current["questions"][key]
        game["current_question"] = None
        game["answered_players"] = []
        await self._check_round_complete(room_code)
        await self.broadcast_game_state(room_code)

    async def connect(self, room_code: str, player_id: str, websocket: WebSocket):
        if room_code not in self.rooms:
            await websocket.close(code=4004, reason="Room not found")
            return
        room = self.rooms[room_code]
        player_count = len([p for p in room["players"].values() if not p.get("is_host")])
        if player_count >= 5:
            await websocket.send_json({"type": "error", "message": "Room is full"})
            await websocket.close(code=4000, reason="Room full")
            return
        room["players"][player_id] = {
            "websocket": websocket,
            "name": "Player...",
            "score": 0,
            "is_host": False,
            "can_answer": False,
        }
        await self.broadcast_room_state(room_code)

    async def disconnect(self, room_code: str, player_id: str):
        if room_code in self.rooms:
            room = self.rooms[room_code]
            if player_id in room["players"]:
                del room["players"][player_id]
            if room.get("host") == player_id:
                room["host"] = None
            if not room["players"]:
                del self.rooms[room_code]
                if room_code in self.games:
                    del self.games[room_code]
            else:
                await self.broadcast_room_state(room_code)

    async def handle_message(self, room_code: str, player_id: str, message: dict):
        if room_code not in self.rooms:
            return
        msg_type = message.get("type")
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
        elif msg_type == "skip_to_final":
            await self._skip_to_final(room_code, player_id, message)
        elif msg_type == "next_round":
            await self._next_round(room_code, player_id, message)
        elif msg_type == "skip_question":
            await self._skip_question(room_code, player_id, message)
        elif msg_type == "answer_attempt":
            await self._handle_answer_attempt(room_code, player_id, message)
        elif msg_type == "evaluate_answer":
            await self._handle_evaluate_answer(room_code, player_id, message)
        elif msg_type == "ping":
            await self.send_to_player(room_code, player_id, {"type": "pong"})

    async def _handle_join(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        name = message.get("name", "Player")
        if player_id in room["players"]:
            room["players"][player_id]["name"] = name
        await self.broadcast_room_state(room_code)

    async def _handle_set_creator(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        room["creator"] = player_id
        room["host"] = player_id
        if player_id in room["players"]:
            room["host_name"] = room["players"][player_id]["name"]
            room["players"][player_id]["is_host"] = True
        await self.broadcast_room_state(room_code)

    async def _handle_start_game(self, room_code: str, player_id: str, message: dict):
        room = self.rooms[room_code]
        if room["creator"] != player_id:
            return
        game = self._create_game(room_code)
        self.games[room_code] = game
        room["status"] = "playing"
        # Random first selector
        player_ids = list(room["players"].keys())
        if player_ids:
            game["current_selector"] = random.choice(player_ids)
        print(f"Game started, selector: {game.get('current_selector')}")
        await self.broadcast_game_state(room_code)

    def _create_game(self, room_code: str) -> dict:
        template = self.rooms[room_code].get("template")
        if template:
            rounds = []
            for tr in template["rounds"]:
                questions = {}
                for cat in tr["categories"]:
                    for q in cat["questions"]:
                        key = f"{cat['name']}_{q['price']}"
                        questions[key] = {
                            "text": q.get("text", ""),
                            "answer": q.get("answer", ""),
                            "price": q["price"],
                            "category": cat["name"],
                            "qmedia": q.get("qmedia", ""),
                            "qmediatype": q.get("qmediatype", ""),
                            "amedia": q.get("amedia", ""),
                            "amediatype": q.get("amediatype", ""),
                            "question_media": q.get("question_media", {}),
                            "answer_media": q.get("answer_media", {})
                        }
                prices = [q["price"] for q in tr["categories"][0]["questions"]]
                rounds.append({"name": tr["name"], "prices": prices, "categories": [c["name"] for c in tr["categories"]], "questions": questions})
            return {"current_round": 0, "current_question": None, "answered_players": [], "last_correct_player": None, "phase": "playing", "rounds": rounds, "final": template.get("final", []), "current_selector": None}
        return {"current_round": 0, "current_question": None, "answered_players": [], "phase": "playing", "rounds": [], "final": [], "current_selector": None}

    async def _handle_select_question(self, room_code, player_id, message):
        game = self.games.get(room_code)
        if not game or game.get("current_selector") != player_id:
            return
        cat = message.get("category")
        price = message.get("price")
        key = f"{cat}_{price}"
        q = game["rounds"][game["current_round"]]["questions"].get(key)
        if q:
            game["current_question"] = {"category": cat, "price": price, "selected_by": player_id, "question": q, "status": "selected"}
            await self.broadcast_game_state(room_code)

    async def _handle_open_question(self, room_code, player_id, message):
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        if not game or player_id != room["host"]:
            return
        if game["current_question"]:
            game["current_question"]["status"] = "open"
            for pid in room["players"]:
                room["players"][pid]["can_answer"] = True
            await self.broadcast_game_state(room_code)

    async def _handle_answer_attempt(self, room_code, player_id, message):
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
            await self.broadcast_game_state(room_code)

    async def _handle_evaluate_answer(self, room_code, player_id, message):
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        if not game or player_id != room["host"]:
            return
        is_correct = message.get("correct", False)
        answering = game["answered_players"][-1] if game["answered_players"] else None
        if answering:
            price = game["current_question"]["price"]
            if is_correct:
                room["players"][answering]["score"] += price
                game["last_correct_player"] = answering
                game["current_selector"] = answering
                key = f"{game['current_question']['category']}_{price}"
                if key in game["rounds"][game["current_round"]]["questions"]:
                    del game["rounds"][game["current_round"]]["questions"][key]
                game["current_question"] = None
                game["answered_players"] = []
                await self._check_round_complete(room_code)
            else:
                room["players"][answering]["score"] -= price
                game["current_question"]["status"] = "open"
                game["answered_players"] = []
                for pid in room["players"]:
                    if pid != answering:
                        room["players"][pid]["can_answer"] = True
            await self.broadcast_game_state(room_code)

    async def _skip_to_final(self, room_code, player_id, message):
        game = self.games.get(room_code)
        if not game: return
        game["current_round"] = 2
        game["current_question"] = None
        game["rounds"][0]["questions"] = {}
        game["rounds"][1]["questions"] = {}
        game["rounds"][2]["questions"] = {}
        game["phase"] = "final"
        await self.broadcast_game_state(room_code)

    async def _next_round(self, room_code, player_id, message):
        game = self.games.get(room_code)
        room = self.rooms[room_code]
        if not game or player_id != room["host"]:
            return
        if game["current_round"] < 2:
            game["current_round"] += 1
            game["current_question"] = None
        elif game["phase"] != "final":
            game["phase"] = "final"
        await self.broadcast_game_state(room_code)

    async def _check_round_complete(self, room_code: str):
        game = self.games.get(room_code)
        if not game:
            return
        if not game["rounds"][game["current_round"]]["questions"]:
            if game["current_round"] < 2:
                game["current_round"] += 1
                game["current_question"] = None
                await self.broadcast_game_state(room_code)
            else:
                game["phase"] = "final"
                await self.broadcast_game_state(room_code)

    async def broadcast_room_state(self, room_code: str):
        if room_code not in self.rooms:
            return
        room = self.rooms[room_code]
        players_info = {}
        for pid, p in room["players"].items():
            players_info[pid] = {"name": p["name"], "score": p["score"], "is_host": False}
        state = {"type": "room_state", "status": room["status"], "players": players_info, "players_count": len(players_info), "max_players": 5, "creator": room["creator"], "host": room["host"], "host_name": room.get("host_name", "")}
        for pid, player in room["players"].items():
            try:
                await player["websocket"].send_json(state)
                print(f"Sent game_state to {pid}")
            except Exception as e:
                print(f"ERROR sending to {pid}: {e}")

    async def broadcast_game_state(self, room_code: str):
        if room_code not in self.rooms:
            return
        room = self.rooms[room_code]
        game = self.games.get(room_code)
        if not game:
            await self.broadcast_room_state(room_code)
            return
        players_info = {}
        for pid, p in room["players"].items():
            players_info[pid] = {"name": p["name"], "score": p["score"], "can_answer": p.get("can_answer", False), "is_host": False}
        sel_id = game.get("current_selector")
        sel_name = room["players"][sel_id]["name"] if sel_id and sel_id in room["players"] else ""
        print(f"Broadcasting game_state to {len(room['players'])} players: {list(room['players'].keys())}, selector={sel_name}")
        for pid, player in room["players"].items():
            try:
                state = {"type": "game_state", "game": game, "players": players_info, "current_player": pid, "current_selector": sel_id, "selector_name": sel_name, "host_name": room.get("host_name", "")}
                await player["websocket"].send_json(state)
                print(f"Sent game_state to {pid}")
            except Exception as e:
                print(f"ERROR sending to {pid}: {e}")

    async def send_to_player(self, room_code: str, player_id: str, message: dict):
        room = self.rooms.get(room_code)
        if room and player_id in room["players"]:
            try:
                await room["players"][player_id]["websocket"].send_json(message)
            except:
                pass

    def get_room_status(self, room_code: str) -> dict:
        if room_code not in self.rooms:
            return {"error": "Room not found", "exists": False}
        room = self.rooms[room_code]
        return {"exists": True, "status": room["status"], "players_count": len(room["players"]), "max_players": 5}
