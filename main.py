import logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

# Basic configuration for a simple test app
app = FastAPI(title="WebSocket Ping Test Server")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ping_server")

@app.websocket("/ws/ping")
async def websocket_ping_endpoint(websocket: WebSocket):
    """
    A very simple WebSocket endpoint that accepts a connection,
    waits for any message, logs it, and sends back a "pong" response.
    """
    await websocket.accept()
    logger.info("Client connected to ping endpoint.")
    
    try:
        while True:
            # Wait for any message from the client
            received_data = await websocket.receive_text()
            logger.info(f"Received message: '{received_data}'")
            
            # Send a simple "pong" response back
            response = {"status": "pong", "original_message": received_data}
            await websocket.send_json(response)
            logger.info(f"Sent response: {response}")

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
    except Exception as e:
        logger.error(f"An error occurred: {e}", exc_info=True)
        # No need to close the websocket here, FastAPI handles it on exception.

if __name__ == "__main__":
    import uvicorn
    # To run this: uvicorn ping_test_server:app --reload --port 8001
    uvicorn.run(app, host="0.0.0.0", port=8001)
