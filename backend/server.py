"""SlyAI Backend - Personal AI Assistant API powered by Claude."""

import os
import json
from datetime import datetime, timezone
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import anthropic

load_dotenv()

app = FastAPI(title="SlyAI", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

SYSTEM_PROMPT = """You are SlyAI, a personal AI assistant. You help the user manage their life — calendar events, reminders, alarms, and general questions.

When the user asks you to do something actionable, respond with BOTH:
1. A natural conversational response
2. A JSON action block wrapped in <action>...</action> tags

Action types and their JSON schemas:

CALENDAR EVENT (recurring or one-time):
<action>{"type": "calendar_event", "title": "Take out recycling", "start_date": "2026-04-08T21:00:00", "recurrence": "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU", "alert_minutes": 30, "notes": "Every other Tuesday night"}</action>

REMINDER:
<action>{"type": "reminder", "title": "Buy groceries", "due_date": "2026-04-02T17:00:00", "notes": "Milk, eggs, bread"}</action>

ALARM:
<action>{"type": "alarm", "title": "Wake up", "time": "06:00", "date": "2026-04-02", "repeats": "weekdays"}</action>

TIMED NOTIFICATION (for "remind me in X minutes/hours"):
<action>{"type": "notification", "title": "Wake up", "body": "Time to wake up!", "delay_seconds": 600}</action>

Rules:
- Today's date/time: {now}
- For recurring events, use iCalendar RRULE format for recurrence
- "Every other Tuesday" = FREQ=WEEKLY;INTERVAL=2;BYDAY=TU
- "Every weekday" = FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
- When the user says "tonight" or "tomorrow", calculate the actual date
- For alarms, "repeats" can be: "once", "weekdays", "weekends", "daily", or specific days like "MO,WE,FR"
- When the user says "remind me in X minutes/hours", ALWAYS use the "notification" type with delay_seconds (e.g. 10 min = 600, 1 hour = 3600)
- Only use "alarm" for absolute clock times like "wake me at 6am". Use "notification" for relative times like "in 10 minutes"
- If the request is just a question or conversation, respond naturally without action tags
- Keep responses short and direct — you're a personal assistant, not a chatbot
- Never say "I can't do that" for calendar/reminder/alarm tasks — always generate the action
"""


class ChatRequest(BaseModel):
    message: str
    conversation_id: str | None = None


class Action(BaseModel):
    type: str
    data: dict


class ChatResponse(BaseModel):
    response: str
    actions: list[dict]
    conversation_id: str | None = None


# Simple in-memory conversation store (single user)
conversations: dict[str, list[dict]] = {}


@app.get("/health")
async def health():
    return {"status": "ok", "service": "slyai", "version": "1.0.0"}


@app.post("/v1/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="ANTHROPIC_API_KEY not configured")

    # Use US Eastern time so Claude calculates correct local dates/times
    from zoneinfo import ZoneInfo
    now = datetime.now(ZoneInfo("America/New_York")).strftime("%Y-%m-%d %H:%M:%S ET")
    system = SYSTEM_PROMPT.replace("{now}", now)

    # Get or create conversation history
    conv_id = req.conversation_id or "default"
    if conv_id not in conversations:
        conversations[conv_id] = []

    conversations[conv_id].append({"role": "user", "content": req.message})

    # Keep last 20 messages to stay within limits
    messages = conversations[conv_id][-20:]

    try:
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1024,
            system=system,
            messages=messages,
        )
    except anthropic.APIError as e:
        raise HTTPException(status_code=502, detail=f"Claude API error: {str(e)}")

    assistant_text = response.content[0].text

    # Store assistant response
    conversations[conv_id].append({"role": "assistant", "content": assistant_text})

    # Parse actions from response
    actions = []
    import re
    action_matches = re.findall(r"<action>(.*?)</action>", assistant_text, re.DOTALL)
    for match in action_matches:
        try:
            action_data = json.loads(match.strip())
            actions.append(action_data)
        except json.JSONDecodeError:
            pass

    # Clean action tags from the display response
    clean_response = re.sub(r"<action>.*?</action>", "", assistant_text, flags=re.DOTALL).strip()

    return ChatResponse(
        response=clean_response,
        actions=actions,
        conversation_id=conv_id,
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
