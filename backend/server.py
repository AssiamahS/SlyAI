"""SlyAI Backend - Personal AI Assistant API.

AI provider chain: Local (llama.cpp) -> Groq (free) -> Claude (fallback)
"""

import os
import re
import json
import httpx
from datetime import datetime, timezone
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import anthropic
from coding_prompt import CODING_SYSTEM_PROMPT

load_dotenv()

app = FastAPI(title="SlyAI", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

SYSTEM_PROMPT = """You are SlyAI, a personal AI assistant. You help the user manage their life — calendar events, reminders, alarms, and general questions.

When the user asks you to do something actionable, respond with BOTH:
1. A natural conversational response
2. A JSON action block wrapped in <action>...</action> tags

Action types and their JSON schemas:

CALENDAR EVENT (recurring or one-time):
<action>{{"type": "calendar_event", "title": "Take out recycling", "start_date": "2026-04-08T21:00:00", "recurrence": "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU", "alert_minutes": 30, "notes": "Every other Tuesday night"}}</action>

REMINDER:
<action>{{"type": "reminder", "title": "Buy groceries", "due_date": "2026-04-02T17:00:00", "notes": "Milk, eggs, bread"}}</action>

ALARM:
<action>{{"type": "alarm", "title": "Wake up", "time": "06:00", "date": "2026-04-02", "repeats": "weekdays"}}</action>

TIMED NOTIFICATION (for "remind me in X minutes/hours"):
<action>{{"type": "notification", "title": "Wake up", "body": "Time to wake up!", "delay_seconds": 600}}</action>

CRITICAL RULES FOR CHOOSING ACTION TYPE:
- "remind me in X minutes/hours" or "in 5 min" → ALWAYS use "notification" with delay_seconds. Calculate: 1 min = 60, 5 min = 300, 10 min = 600, 1 hour = 3600.
- "wake me at 6am" or "at 11:19 AM" or any SPECIFIC CLOCK TIME → ALWAYS use "alarm" with time="HH:MM" and date="YYYY-MM-DD" and repeats="once".
- "remind me to buy groceries tomorrow" → use "reminder" with due_date.
- "add a meeting at 2pm" → use "calendar_event" with start_date.
- NEVER use notification with delay_seconds=600 as a default. ALWAYS calculate the correct delay from the user's request.

Other rules:
- Today's date/time: {now}
- For recurring events, use iCalendar RRULE format
- "Every other Tuesday" = FREQ=WEEKLY;INTERVAL=2;BYDAY=TU
- "Every weekday" = FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
- When the user says "tonight" or "tomorrow", calculate the actual date
- For alarms, "repeats" can be: "once", "weekdays", "weekends", "daily", or specific days like "MO,WE,FR"
- If the request is just a question or conversation, respond naturally without action tags
- Keep responses short and direct — you're a personal assistant, not a chatbot
- Never say "I can't do that" for calendar/reminder/alarm tasks — always generate the action
"""


class ChatRequest(BaseModel):
    message: str
    conversation_id: str | None = None


class ChatResponse(BaseModel):
    response: str
    actions: list[dict]
    conversation_id: str | None = None
    provider: str | None = None


# Simple in-memory conversation store (single user)
conversations: dict[str, list[dict]] = {}


def get_system_prompt() -> str:
    from zoneinfo import ZoneInfo
    now = datetime.now(ZoneInfo("America/New_York")).strftime("%Y-%m-%d %H:%M:%S ET")
    # Replace placeholder first, then un-escape double braces so models see real JSON
    prompt = SYSTEM_PROMPT.replace("{now}", now)
    prompt = prompt.replace("{{", "{").replace("}}", "}")
    return prompt


def parse_actions(text: str) -> tuple[str, list[dict]]:
    """Extract action JSON blocks and return clean text + actions list.
    Handles both closed </action> tags and unclosed <action>{...} from smaller models.
    """
    actions = []
    # Try closed tags first
    for match in re.findall(r"<action>(.*?)</action>", text, re.DOTALL):
        try:
            actions.append(json.loads(match.strip()))
        except json.JSONDecodeError:
            pass
    # Fallback: unclosed <action> tags (common with small local models)
    if not actions:
        for match in re.findall(r"<action>(\{.*?\})", text, re.DOTALL):
            try:
                actions.append(json.loads(match.strip()))
            except json.JSONDecodeError:
                pass
    clean = re.sub(r"<action>.*?(?:</action>|$)", "", text, flags=re.DOTALL).strip()
    return clean, actions


def fix_actions(user_message: str, actions: list[dict]) -> list[dict]:
    """Post-process actions to fix common model mistakes.
    If user said 'in X minutes/hours' but model returned wrong type, fix it.
    """
    msg = user_message.lower()
    fixed = []
    for action in actions:
        a = dict(action)
        # Normalize word numbers to digits
        word_nums = {"one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
                     "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
                     "fifteen": "15", "twenty": "20", "thirty": "30", "forty five": "45", "forty-five": "45"}
        nmsg = msg
        for word, digit in word_nums.items():
            nmsg = nmsg.replace(word, digit)
        # Detect "in X minute(s)/hour(s)/second(s)" pattern
        m = re.search(r"in\s+(\d+)\s*(min|minute|hour|hr|second|sec)", nmsg)
        if m:
            amount = int(m.group(1))
            unit = m.group(2)
            if unit.startswith("hour") or unit.startswith("hr"):
                delay = amount * 3600
            elif unit.startswith("sec"):
                delay = amount
            else:
                delay = amount * 60
            # Force notification type with correct delay
            a = {
                "type": "notification",
                "title": a.get("title", "SlyAI Reminder"),
                "body": a.get("body") or a.get("notes") or "Time's up!",
                "delay_seconds": delay,
            }
        # Detect "at HH:MM" pattern — force alarm type with correct time
        elif re.search(r"at\s+\d{1,2}[:\s]?\d{0,2}\s*(am|pm|AM|PM)", msg):
            time_match = re.search(r"at\s+(\d{1,2})[:\s]?(\d{0,2})\s*(am|pm|AM|PM)", msg)
            if time_match:
                hour = int(time_match.group(1))
                minute = int(time_match.group(2)) if time_match.group(2) else 0
                ampm = time_match.group(3).lower()
                if ampm == "pm" and hour != 12:
                    hour += 12
                if ampm == "am" and hour == 12:
                    hour = 0
                from zoneinfo import ZoneInfo
                now = datetime.now(ZoneInfo("America/New_York"))
                a = {
                    "type": "alarm",
                    "title": a.get("title", "SlyAI Alarm"),
                    "time": f"{hour:02d}:{minute:02d}",
                    "date": now.strftime("%Y-%m-%d"),
                    "repeats": "once",
                }
        fixed.append(a)
    return fixed


# ---------- Provider 1: Local llama.cpp ----------

LOCAL_URL = os.getenv("LOCAL_LLM_URL", "http://127.0.0.1:8081")

async def try_local(system: str, messages: list[dict]) -> str | None:
    """Try local llama.cpp server. Returns None if unavailable."""
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            # llama.cpp uses OpenAI-compatible API
            resp = await client.post(
                f"{LOCAL_URL}/v1/chat/completions",
                json={
                    "messages": [{"role": "system", "content": system}] + messages,
                    "max_tokens": 1024,
                    "temperature": 0.7,
                },
            )
            if resp.status_code == 200:
                data = resp.json()
                return data["choices"][0]["message"]["content"]
    except (httpx.ConnectError, httpx.ReadTimeout, httpx.ConnectTimeout):
        pass
    return None


# ---------- Provider 2: Groq (free tier) ----------

GROQ_API_KEY = os.getenv("GROQ_API_KEY")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")

async def try_groq(system: str, messages: list[dict]) -> str | None:
    """Try Groq free tier. Returns None if unavailable or no key."""
    if not GROQ_API_KEY:
        return None
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
                json={
                    "model": GROQ_MODEL,
                    "messages": [{"role": "system", "content": system}] + messages,
                    "max_tokens": 1024,
                    "temperature": 0.7,
                },
            )
            if resp.status_code == 200:
                data = resp.json()
                return data["choices"][0]["message"]["content"]
    except (httpx.ConnectError, httpx.ReadTimeout, httpx.ConnectTimeout):
        pass
    return None


# ---------- Provider 3: Claude (fallback) ----------

def try_claude(system: str, messages: list[dict]) -> str | None:
    """Claude API as final fallback."""
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        return None
    try:
        client = anthropic.Anthropic(api_key=api_key)
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1024,
            system=system,
            messages=messages,
        )
        return response.content[0].text
    except Exception:
        return None


# ---------- Notification status tracking ----------

notify_log: list[dict] = []

class NotifyStatus(BaseModel):
    event: str
    detail: str
    timestamp: str | None = None

@app.post("/v1/notify-status")
async def notify_status(req: NotifyStatus):
    entry = {"event": req.event, "detail": req.detail, "timestamp": req.timestamp or datetime.now().isoformat()}
    notify_log.append(entry)
    # Keep last 50 entries
    if len(notify_log) > 50:
        notify_log.pop(0)
    import logging
    logging.getLogger("slyai").warning(f"NOTIFY: {entry}")
    return {"ok": True}

@app.get("/v1/notify-log")
async def get_notify_log():
    return {"log": notify_log}


@app.get("/health")
async def health():
    # Check which providers are available
    providers = []
    try:
        async with httpx.AsyncClient(timeout=3) as c:
            r = await c.get(f"{LOCAL_URL}/health")
            if r.status_code == 200:
                providers.append("local")
    except Exception:
        pass
    if GROQ_API_KEY:
        providers.append("groq")
    if os.getenv("ANTHROPIC_API_KEY"):
        providers.append("claude")
    return {"status": "ok", "service": "slyai", "version": "2.0.0", "providers": providers}


@app.post("/v1/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    system = get_system_prompt()

    # Conversation history
    conv_id = req.conversation_id or "default"
    if conv_id not in conversations:
        conversations[conv_id] = []
    conversations[conv_id].append({"role": "user", "content": req.message})
    messages = conversations[conv_id][-20:]

    import logging
    logger = logging.getLogger("slyai")

    # Try providers in order: local -> groq -> claude
    assistant_text = None
    provider = None

    # 1. Local llama.cpp
    assistant_text = await try_local(system, messages)
    if assistant_text:
        provider = "local"
        logger.warning(f"LOCAL RAW: {assistant_text!r}")

    # 2. Groq free tier
    if not assistant_text:
        assistant_text = await try_groq(system, messages)
        if assistant_text:
            provider = "groq"

    # 3. Claude fallback
    if not assistant_text:
        assistant_text = try_claude(system, messages)
        if assistant_text:
            provider = "claude"

    if not assistant_text:
        raise HTTPException(status_code=502, detail="All AI providers failed")

    conversations[conv_id].append({"role": "assistant", "content": assistant_text})
    clean_response, actions = parse_actions(assistant_text)
    actions = fix_actions(req.message, actions)

    # If local model only returned actions with no text, generate a short confirmation
    if not clean_response and actions:
        action_types = [a.get("type", "") for a in actions]
        if "notification" in action_types:
            clean_response = "Got it, I'll remind you."
        elif "calendar_event" in action_types:
            clean_response = "Added to your calendar."
        elif "reminder" in action_types:
            clean_response = "Reminder set."
        elif "alarm" in action_types:
            clean_response = "Alarm set."
        else:
            clean_response = "Done."

    return ChatResponse(
        response=clean_response,
        actions=actions,
        conversation_id=conv_id,
        provider=provider,
    )


@app.post("/v1/code", response_model=ChatResponse)
async def code_chat(req: ChatRequest):
    system = CODING_SYSTEM_PROMPT

    # Conversation history
    conv_id = req.conversation_id or "default-code"
    if conv_id not in conversations:
        conversations[conv_id] = []
    conversations[conv_id].append({"role": "user", "content": req.message})
    messages = conversations[conv_id][-30:]

    import logging
    logger = logging.getLogger("slyai")

    # Try providers in order: local -> groq -> claude
    assistant_text = None
    provider = None

    # 1. Local llama.cpp
    assistant_text = await try_local(system, messages)
    if assistant_text:
        provider = "local"
        logger.warning(f"CODE LOCAL RAW: {assistant_text!r}")

    # 2. Groq free tier
    if not assistant_text:
        assistant_text = await try_groq(system, messages)
        if assistant_text:
            provider = "groq"

    # 3. Claude fallback
    if not assistant_text:
        assistant_text = try_claude(system, messages)
        if assistant_text:
            provider = "claude"

    if not assistant_text:
        raise HTTPException(status_code=502, detail="All AI providers failed")

    conversations[conv_id].append({"role": "assistant", "content": assistant_text})

    return ChatResponse(
        response=assistant_text,
        actions=[],
        conversation_id=conv_id,
        provider=provider,
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
