import os
import json
import logging
import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import google.generativeai as genai
from google.generativeai.types import HarmCategory, HarmBlockThreshold
import uvicorn
from dotenv import load_dotenv

# --- Configuration ---
load_dotenv(dotenv_path=".env")

APP_NAME = "KineTrack AI Coach Backend"
VERSION = "0.4.0" # Version updated for summary feature
HOST = "0.0.0.0"
PORT = 8000
DEBUG = True

# --- Gemini API Configuration ---
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# Use a model that is good with video, like 1.5 Pro or Flash.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.0-flash") 

SUMMARY_SYSTEM_PROMPT = """
You are an expert fitness coach and personal trainer named 'Kine'.
Your goal is to provide a concise, encouraging, and helpful summary of a user's workout session based on a video and a list of real-time corrections that were already given.

Rules:
- Start with positive reinforcement about their effort.
- Look at the provided real-time corrections and the video to identify a primary area for improvement.
- Provide ONE key, actionable tip for them to focus on next time.
- Keep the entire summary to 3-4 sentences.
- Do not analyze the video frame-by-frame. Provide a holistic summary.
- Your tone should be encouraging, not critical.
"""

# --- FastAPI App Initialization ---
app = FastAPI(title=APP_NAME, version=VERSION)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"],
)

# --- Logging ---
logging.basicConfig(level=logging.DEBUG if DEBUG else logging.INFO)
logger = logging.getLogger("kinetrack")

# --- Gemini Model Initialization ---
if not GEMINI_API_KEY:
    raise RuntimeError("GEMINI_API_KEY not set in environment!")
genai.configure(api_key=GEMINI_API_KEY)

model = genai.GenerativeModel(
    GEMINI_MODEL,
    system_instruction=SUMMARY_SYSTEM_PROMPT,
    safety_settings={
        HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_NONE,
        HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_NONE,
        HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_NONE,
        HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_NONE,
    }
)

@app.get("/health")
def health():
    return {"status": "ok", "app": APP_NAME, "version": VERSION}

@app.websocket("/ws/live_coaching")
async def live_coaching(websocket: WebSocket):
    await websocket.accept()
    logger.info("Client connected for workout session.")
    
    video_frames = []
    
    try:
        # 1. Initial Handshake
        initial_message = await websocket.receive_text()
        data = json.loads(initial_message)
        exercise = data.get("exercise_name", "the user's exercise")
        logger.info(f"Starting session for: {exercise}")

        # 2. Receive Frames and listen for End Command
        while True:
            message = await websocket.receive()
            if "bytes" in message:
                video_frames.append(message["bytes"])
            elif "text" in message:
                end_data = json.loads(message["text"])
                if end_data.get("action") == "end_session":
                    logger.info("End of session signal received.")
                    corrections = end_data.get("corrections", [])
                    break # Exit loop to start summary generation
        
        # 3. Generate Summary
        if not video_frames:
            await websocket.send_text("[ERROR] No video frames were received to generate a summary.")
            return

        logger.info(f"Generating summary for {len(video_frames)} frames...")
        
        # Prepare content for Gemini API
        image_parts = [{"mime_type": "image/jpeg", "data": frame} for frame in video_frames]
        
        corrections_text = "\n- ".join(corrections) if corrections else "None"
        prompt = (
            f"The user just completed a set of {exercise}. "
            f"Here are the real-time corrections that were provided by a heuristic model:\n"
            f"- {corrections_text}\n\n"
            f"Please analyze the attached video frames and provide a final summary."
        )
        
        # Send to Gemini and stream response
        response_stream = model.generate_content([prompt] + image_parts, stream=True)
        
        for chunk in response_stream:
            if chunk.text:
                await websocket.send_text(chunk.text)
        
        await websocket.send_text("[END_OF_SUMMARY]")

    except WebSocketDisconnect:
        logger.info("Client disconnected.")
    except json.JSONDecodeError:
        logger.error("Failed to decode incoming JSON message.")
        await websocket.close(code=1003, reason="Invalid JSON format")
    except Exception as e:
        error_message = f"A server-side error occurred: {str(e)}"
        logger.error(error_message, exc_info=True)
        if websocket.client_state.name == 'CONNECTED':
            await websocket.send_text(f"[ERROR] {error_message}")
    finally:
        logger.info("Session ended.")
        if websocket.client_state.name == 'CONNECTED':
            await websocket.close()

if __name__ == "__main__":
    uvicorn.run("backend:app", host=HOST, port=PORT, reload=DEBUG)
