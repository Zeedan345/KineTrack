import json
import logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import asyncio

# Import all your analyzer classes
# Make sure you have exercise_analyzer.py, pushup_analyzer.py, etc. in the same directory
from pushup_analyzer import PushupAnalyzer
from squat_analyzer import SquatAnalyzer

# Basic configuration for the app
app = FastAPI(title="KineTrack Heuristic Analyzer")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("kinetrack")

# --- Analyzer Factory ---
# This dictionary maps exercise names to your analyzer classes.
ANALYZER_CLASSES = {
    "pushups": PushupAnalyzer,
    "squats": SquatAnalyzer,
}
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import asyncio

@app.websocket("/ws/analyze")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    logger.info("Client connected. Waiting for 'start' command.")
    
    analyzer = None
    exercise_type = None

    try:
        # --- STAGE 1: Idle loop ---
        while analyzer is None:
            try:
                # Add timeout to prevent hanging
                raw_data = await asyncio.wait_for(
                    websocket.receive_text(), 
                    timeout=30.0
                )
            except asyncio.TimeoutError:
                # Send ping to keep connection alive
                await websocket.send_json({"type": "ping"})
                continue
            
            try:
                request_data = json.loads(raw_data)
            except json.JSONDecodeError:
                logger.warning(f"Received non-JSON message, ignoring: {raw_data}")
                continue

            message_type = request_data.get("type")

            if message_type == "start":
                exercise_type = request_data.get("exercise")
                
                if exercise_type in ANALYZER_CLASSES:
                    analyzer_class = ANALYZER_CLASSES[exercise_type]
                    analyzer = analyzer_class()
                    logger.info(f"Started analyzer for '{exercise_type}'.")
                    await websocket.send_json({"status": "started", "exercise": exercise_type})
                    break 
                else:
                    logger.error(f"Unknown exercise type: {exercise_type}")
                    await websocket.send_json({"status": "error", "message": f"Unknown exercise type: {exercise_type}"})
            
            elif message_type == "ping":
                await websocket.send_json({"type": "pong"})
            
            else:
                logger.warning(f"Unexpected message in idle state: {request_data}")

        # --- STAGE 2: Main loop ---
        while True:
            try:
                raw_data = await asyncio.wait_for(
                    websocket.receive_text(),
                    timeout=30.0
                )
            except asyncio.TimeoutError:
                logger.warning("No frame received for 30s, closing connection")
                break
            
            try:
                frame_request = json.loads(raw_data)
            except json.JSONDecodeError:
                logger.warning(f"Received non-JSON frame data: {raw_data}")
                continue

            # Handle pings in main loop too
            if frame_request.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
                continue

            frame_id = frame_request.get("frame_id")
            frame_data_for_analyzer = frame_request.get("frame")

            if not all([frame_id is not None, frame_data_for_analyzer]):
                await websocket.send_json({
                    "message": "Invalid frame format",
                    "message_id": frame_id or -1
                })
                continue
            
            feedback_list = analyzer.process_frame(frame_data_for_analyzer)
            feedback_message = " ".join(feedback_list) if feedback_list else "Good form."

            await websocket.send_json({
                "message": feedback_message,
                "message_id": frame_id
            })

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)
        if websocket.client_state.name == 'CONNECTED':
            await websocket.close(code=1011, reason=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

