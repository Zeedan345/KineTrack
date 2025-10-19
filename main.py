import json
import logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse

# Import all your analyzer classes
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
    """
    await websocket.accept()
    logger.info("Client connected. Waiting for exercise selection.")
    
    analyzer = None

    try:
        # --- STAGE 1: Wait for the 'start' message from the client ---
        while True:
            setup_data = await websocket.receive_json()
            
            if setup_data.get("type") == "start":
                exercise_type = setup_data.get("exercise")
                
                if exercise_type in ANALYZER_CLASSES:
                    # Create the correct analyzer instance
                    analyzer_class = ANALYZER_CLASSES[exercise_type]
                    analyzer = analyzer_class()
                    logger.info(f"Starting analysis for '{exercise_type}'.")
                    await websocket.send_json({"status": "started", "exercise": exercise_type})
                    # Break out of the setup loop to start processing frames
                    break 
                else:
                    logger.error(f"Unknown exercise type received: {exercise_type}")
                    await websocket.send_json({"status": "error", "message": f"Unknown exercise type: {exercise_type}"})
            else:
                logger.warning(f"Received unexpected message while waiting for start: {setup_data}")
                await websocket.send_json({"status": "error", "message": "Waiting for a 'start' message to begin."})

        # --- STAGE 2: Main loop to process frames after being started ---
        while True:
            data = await websocket.receive_text()
            frame_data = json.loads(data)
            
            feedback = analyzer.process_frame(frame_data)
            
            if feedback:
                await websocket.send_json({
                    "type": "feedback",
                    "messages": feedback
                })
            
            await websocket.send_json({
                "type": "stats",
                "rep_count": analyzer.rep_count
            })

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
        if analyzer:
            logger.info(f"Session Summary - Total Reps: {analyzer.rep_count}")
            logger.info(f"Session Feedback Log: {analyzer.feedback_log}")
    except Exception as e:
        logger.error(f"An error occurred: {e}")
        await websocket.close(code=1011, reason=f"An internal error occurred: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

