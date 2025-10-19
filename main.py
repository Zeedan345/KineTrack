import json
import logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import base64 # For debugging image data if needed

# Import all your analyzer classes
from pushup_analyzer import PushupAnalyzer
from squat_analyzer import SquatAnalyzer
# Ensure you have a base class file if your analyzers inherit from it
from exercise_analyzer import ExerciseAnalyzer


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
    A simplified WebSocket endpoint that processes frames as they arrive.
    It determines the exercise type from the first valid message.
    """
    await websocket.accept()
    logger.info("Client connected. Ready to analyze frames.")
    
    analyzer: ExerciseAnalyzer = None
    exercise_type: str = None

    try:
        while True:
            # Wait for a message from the client
            data = await websocket.receive_text()
            
            try:
                # --- 1. Parse the incoming message ---
                message = json.loads(data)
                
                msg_type = message.get("type")

                if msg_type == "pose":
                    pose_name = message.get("pose_name")
                    frame_id = message.get("frame_id")
                    frame_data = message.get("frame") # This contains the landmark data

                # frame_data = {'a': 1} #TODO: Integrate Kevin's code
                if not all([pose_name, frame_id is not None, frame_data]):
                    await websocket.send_json({
                        "message": "Invalid message format. Required keys: 'pose', 'frame_id', 'frame'.",
                        "message_id": frame_id or -1
                    })
                    continue

                # --- 3. Instantiate the correct analyzer on the first frame ---
                if analyzer is None:
                    if pose_name in ANALYZER_CLASSES:
                        analyzer_class = ANALYZER_CLASSES[pose_name]
                        analyzer = analyzer_class()
                        exercise_type = pose_name
                        logger.info(f"First frame received. Starting analysis for '{exercise_type}'.")
                    else:
                        await websocket.send_json({
                            "message": f"Unknown pose: '{pose_name}'. Cannot start analysis.",
                            "message_id": frame_id
                        })
                        # Close the connection if the pose is invalid on the first try
                        await websocket.close(code=1008, reason="Invalid pose type")
                        break
                
                # --- 4. Process the frame and get feedback ---
                # feedback_list = analyzer.process_frame(frame_data)
                feedback_list = ["Good form."] #TODO: Integrate Kevin's code
                feedback_message = " ".join(feedback_list) if feedback_list else "Good form."

                # --- 5. Send the response back to the client ---
                await websocket.send_json({
                    "message": feedback_message,
                    "message_id": frame_id
                })

            except json.JSONDecodeError:
                logger.error(f"Received invalid JSON: {data}")
                await websocket.send_json({"message": "Invalid JSON format.", "message_id": -1})
            except KeyError as e:
                logger.error(f"Missing key in message: {e}")
                await websocket.send_json({"message": f"Missing required key in message: {e}", "message_id": -1})

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
        if analyzer:
            logger.info(f"Final session summary for '{exercise_type}': {analyzer.rep_count} reps.")
            logger.info(f"Feedback Log: {analyzer.feedback_log}")
            
    except Exception as e:
        logger.error(f"An unexpected error occurred: {e}", exc_info=True)
        # FastAPI will handle closing the connection on unhandled exceptions.

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

