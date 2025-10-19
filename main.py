import json
import logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

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

@app.websocket("/ws/analyze")
async def websocket_endpoint(websocket: WebSocket):
    """
    A dynamic WebSocket endpoint that waits for a start command before analyzing.
    Handles an initial "idle" phase where it can process pings.
    """
    await websocket.accept()
    logger.info("Client connected. Waiting for 'start' command.")
    
    analyzer = None
    exercise_type = None

    try:
        # --- STAGE 1: Idle loop, waiting for the 'start' message ---
        while analyzer is None:
            request_data = await websocket.receive_json()
            
            message_type = request_data.get("type")

            if message_type == "start":
                exercise_type = request_data.get("exercise")
                
                if exercise_type in ANALYZER_CLASSES:
                    analyzer_class = ANALYZER_CLASSES[exercise_type]
                    analyzer = analyzer_class()
                    logger.info(f"Received start command. Initializing analyzer for '{exercise_type}'.")
                    await websocket.send_json({"status": "started", "exercise": exercise_type})
                    # Break out of the setup loop to start processing frames
                    break 
                else:
                    logger.error(f"Unknown exercise type received: {exercise_type}")
                    await websocket.send_json({"status": "error", "message": f"Unknown exercise type: {exercise_type}"})
            
            elif message_type == "ping":
                # Handle keep-alive pings from the client
                await websocket.send_json({"type": "pong"})
            
            else:
                logger.warning(f"Received unexpected message while in idle state: {request_data}")
                await websocket.send_json({"status": "waiting", "message": "Awaiting 'start' command to begin analysis."})

        # --- STAGE 2: Main loop to process frames after being started ---
        while True:
            # Now we expect the frame data format you described previously
            frame_request = await websocket.receive_json()

            frame_id = frame_request.get("frame_id")
            frame_data_for_analyzer = frame_request.get("frame")

            # Validate the frame data format
            if not all([frame_id is not None, frame_data_for_analyzer]):
                 await websocket.send_json({
                    "message": "Invalid frame format. Required keys are 'frame_id' and 'frame'.",
                    "message_id": frame_id or -1
                })
                 continue
            
            feedback_list = analyzer.process_frame(frame_data_for_analyzer)
            
            # Format and send the response
            feedback_message = " ".join(feedback_list) if feedback_list else "Good form."

            await websocket.send_json({
                "message": feedback_message,
                "message_id": frame_id
            })

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
        if analyzer:
            logger.info(f"Session Summary for '{exercise_type}' - Total Reps: {analyzer.rep_count}")
            logger.info(f"Session Feedback Log: {analyzer.feedback_log}")
    except Exception as e:
        logger.error(f"An error occurred: {e}")
        if websocket.client_state.name == 'CONNECTED':
            await websocket.close(code=1011, reason=f"An internal error occurred: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

