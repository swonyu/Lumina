#!/bin/bash
# Lumina Rich Coach API Tester
# Uses realistic context matching the actual app

set -e

KEY="${XAI_API_KEY}"
SCENARIO=""
QUESTION=""
SIMPLE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --scenario) SCENARIO="$2"; shift 2 ;;
        --simple) SIMPLE=true; shift ;;
        *) QUESTION="$1"; shift ;;
    esac
done

[ -z "$KEY" ] && { echo "XAI_API_KEY required"; exit 1; }
[ -z "$QUESTION" ] && QUESTION="How do I build better consistency with training?"

echo "Testing Lumina coach format..."

if [ "$SIMPLE" = true ]; then
    SYSTEM="You are a helpful assistant."
else
    if [ -n "$SCENARIO" ] && [ -f rich_coach_contexts.json ]; then
        CTX=$(jq -r --arg s "$SCENARIO" '
            .scenarios[] | select(.name == $s) | .context |
            "User: \(.profile.name), \(.profile.age)y, Goal: \(.profile.goal)\n" +
            "Energy: \(.latest_health.energy)/10 | Sleep: \(.latest_health.sleep)h | HRV: \(.latest_health.hrv)\n" +
            "Habits: \(.active_habits) active, avg streak \(.avg_habit_streak) (\(.coach_suggested_habits) coach-suggested)\n" +
            "Insights: \(.recent_insights)\n" +
            "Streak: \(.current_streak) days\n" +
            "Memory: \(.long_term_memory)"
        ' rich_coach_contexts.json)
    else
        CTX="User: Alex 28y Build Muscle intermediate. Energy 6/10. 3 active habits (avg streak 11). Evening walk coach-suggested with low adherence. Recent photo showed good upper body progress."
    fi

    SYSTEM="You are Lumina, a wise, empathetic AI coach.

Core traits: emotionally intelligent, pattern-aware, prioritizes sustainability, honest but kind, celebrates consistency.

Current context:
$CTX

User said: \"$QUESTION\"

Respond empathetically, reference patterns, give one realistic suggestion, ask a good question.
Append ACTION_SUGGESTION:TYPE|... only when genuinely useful."
fi

PAYLOAD=$(jq -n \
    --arg model "grok-3-latest" \
    --arg sys "$SYSTEM" \
    --arg user "$QUESTION" \
    '{
        model: $model,
        messages: [
            {role: "system", content: $sys},
            {role: "user", content: $user}
        ],
        temperature: 0.7,
        max_tokens: 400
    }')

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $KEY" \
    -d "$PAYLOAD" \
    https://api.x.ai/v1/chat/completions)

STATUS=$(echo "$RESPONSE" | tail -1 | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$STATUS" != "200" ]; then
    echo "Error ($STATUS)"
    echo "$BODY" | jq .
    exit 1
fi

echo "✅ Response:"
echo "────────────────────────────────────"
echo "$BODY" | jq -r '.choices[0].message.content'
echo "────────────────────────────────────"
echo "Usage: $(echo "$BODY" | jq -c '.usage')"
