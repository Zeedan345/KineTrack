import asyncio
import json
import websockets
import os

# --- Configuration ---
WEBSOCKET_URL = "ws://localhost:8000/ws/live_coaching"
TEST_IMAGE_PATH = "test_images/squat_form.jpg" 
EXERCISE_NAME = "Bodyweight Squat"
FRAMES_TO_SEND = 5
DELAY_BETWEEN_FRAMES = 0.5 # Send frames faster

# Mock corrections that a heuristic model would generate
MOCK_HEURISTIC_CORRECTIONS = [
    "Knees caved in slightly on rep 2.",
    "Good depth on reps 1, 3, and 5.",
    "Didn't go quite deep enough on rep 4."
]

async def run_test_client():
    """
    Simulates a client performing a workout, then requests a summary.
    """
    print(f"--- KineTrack Test Client (Summary Mode) ---")
    
    if not os.path.exists(TEST_IMAGE_PATH):
        print(f"\n[ERROR] Test image not found at '{TEST_IMAGE_PATH}'")
        return

    print(f"Connecting to {WEBSOCKET_URL}...")
    try:
        async with websockets.connect(WEBSOCKET_URL, ping_timeout=60) as websocket:
            print("[SUCCESS] Connected to the server.")

            # 1. Send initial setup info
            initial_data = {"exercise_name": EXERCISE_NAME}
            print(f"Sending setup info: {json.dumps(initial_data)}")
            await websocket.send(json.dumps(initial_data))

            # Start a listener task to receive the final summary
            receive_task = asyncio.create_task(receive_summary(websocket))

            # 2. Send a stream of frames
            print(f"\nSending {FRAMES_TO_SEND} frames to simulate the workout...")
            with open(TEST_IMAGE_PATH, "rb") as f:
                image_bytes = f.read()
            for i in range(FRAMES_TO_SEND):
                print(f"> Sending frame {i + 1}/{FRAMES_TO_SEND}")
                await websocket.send(image_bytes)
                await asyncio.sleep(DELAY_BETWEEN_FRAMES)

            # 3. Send the "end session" command with mock corrections
            print("\nWorkout finished. Requesting summary...")
            end_session_data = {
                "action": "end_session",
                "corrections": MOCK_HEURISTIC_CORRECTIONS
            }
            await websocket.send(json.dumps(end_session_data))

            # 4. Wait for the summary to be received
            await receive_task
            print("\n--- Test Finished ---")

    except websockets.exceptions.ConnectionClosed as e:
        print(f"\n[ERROR] Connection closed: {e}")
    except ConnectionRefusedError:
        print("\n[ERROR] Connection refused. Is the backend server running?")
    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}")

async def receive_summary(websocket):
    """Listens for and prints the final summary from the server."""
    full_summary = ""
    print("\nWaiting for workout summary...")
    try:
        async for message in websocket:
            if message.startswith("[ERROR]"):
                print(f"< SERVER ERROR: {message}")
                full_summary = ""
                break
            elif message == "[END_OF_SUMMARY]":
                print("\n" + "="*50)
                print("Final Workout Summary:")
                print(full_summary.strip())
                print("="*50)
                full_summary = ""
                break # Summary is complete
            else:
                full_summary += message
    except websockets.exceptions.ConnectionClosed:
        print("[INFO] Server connection closed while waiting for summary.")


if __name__ == "__main__":
    asyncio.run(run_test_client())
