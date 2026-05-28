#!/bin/sh
# Xcode Cloud post-clone script for Lumina

echo "Lumina - Post Clone Script"

# === XAI API Key (Critical for AI Coach features) ===
# Add this in Xcode Cloud Workflow → Environment as a **Secret**:
#   Name: XAI_API_KEY
#   Value: your real key from console.x.ai
#   Type: Secret
#
# The app reads it at runtime via:
# ProcessInfo.processInfo.environment["XAI_API_KEY"]

if [ -n "$XAI_API_KEY" ]; then
    echo "✅ XAI_API_KEY detected — full Grok-powered coach features enabled."
else
    echo "⚠️  XAI_API_KEY not found. AI coach will use local fallbacks only."
    echo "   Add it as a Secret in your Xcode Cloud workflow environment."
fi

# === App Group for Widget + Live Activity (already configured in entitlements) ===
# No extra action needed if group.SA.Lumina is set in the workflow capabilities.

echo "Post-clone setup complete."
exit 0
