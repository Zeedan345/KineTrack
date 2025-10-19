import asyncio
import json
import logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from pushup_analyzer import PushupAnalyzer

# Basic configuration for the app
app = FastAPI(title="KineTrack Heuristic Analyzer")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("kinetrack")

# Serve the frontend HTML for easy testing
@app.get("/", response_class=HTMLResponse)
async def get():
    with open("frontend_example.html") as f:
        return HTMLResponse(content=f.read(), status_code=200)

@app.websocket("/ws/analyze/pushups")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for real-time push-up analysis.
    """
    await websocket.accept()
    logger.info("Client connected for push-up analysis.")
    
    # Create a new analyzer instance for each client connection
    analyzer = PushupAnalyzer()

    try:
        while True:
            # Receive data from the frontend
            data = await websocket.receive_text()
            frame_data = json.loads(data)
            
            # Process the frame using your existing logic
            feedback = analyzer.process_frame(frame_data)
            
            # If there's new feedback, send it back to the frontend
            if feedback:
                await websocket.send_json({
                    "type": "feedback",
                    "messages": feedback
                })
            
            # Always send back the current rep count
            await websocket.send_json({
                "type": "stats",
                "rep_count": analyzer.rep_count
            })

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
        # Log the final results when the session ends
        logger.info(f"Session Summary - Total Reps: {analyzer.rep_count}")
        logger.info(f"Session Feedback Log: {analyzer.feedback_log}")
    except Exception as e:
        logger.error(f"An error occurred: {e}")
        await websocket.close(code=1011, reason=f"An internal error occurred: {e}")

if __name__ == "__main__":
    import uvicorn
    # To run this: uvicorn main:app --reload
    uvicorn.run(app, host="0.0.0.0", port=8000)
