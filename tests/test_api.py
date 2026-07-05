import requests
import json

BASE_URL = "http://localhost:8000"

print("Testing API...")
print("-" * 50)

# Health
r = requests.get(f"{BASE_URL}/health")
print(f"Health: {r.json()}")

# Create room
r = requests.post(f"{BASE_URL}/api/create_room")
data = r.json()
room_code = data.get("room_code")
print(f"Room created: {room_code}")

# Check room
if room_code:
    r = requests.get(f"{BASE_URL}/api/room/{room_code}")
    print(f"Room info: {json.dumps(r.json(), indent=2)}")

print("Tests complete!")
