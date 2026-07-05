
import requests
import json
import webbrowser

BASE_URL = "http://localhost:8000"

print("Testing Svoya Igra API...")
print("-" * 50)

# Health check
print("\n1. Health Check:")
try:
    response = requests.get(f"{BASE_URL}/health")
    print(f"   Status: {response.status_code}")
    print(f"   Response: {response.json()}")
except Exception as e:
    print(f"   Error: {e}")

# Create room
print("\n2. Create Room:")
try:
    response = requests.post(f"{BASE_URL}/api/create_room")
    data = response.json()
    print(f"   Status: {response.status_code}")
    print(f"   Room code: {data.get('room_code')}")
    print(f"   Status: {data.get('status')}")
    
    # Check room
    room_code = data.get('room_code')
    if room_code:
        print(f"\n3. Check Room {room_code}:")
        response = requests.get(f"{BASE_URL}/api/room/{room_code}")
        print(f"   Status: {response.status_code}")
        print(f"   Info: {json.dumps(response.json(), indent=2, ensure_ascii=False)}")
except Exception as e:
    print(f"   Error: {e}")

# Open docs
print("\n4. Opening API docs...")
try:
    webbrowser.open(f"{BASE_URL}/docs")
    print("   Browser opened!")
except:
    print(f"   Open manually: {BASE_URL}/docs")

print("\nTesting complete!")
