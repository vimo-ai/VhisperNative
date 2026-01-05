#!/bin/bash
# Reset accessibility permission for Vhisper
# Run this after rebuilding the app, then restart Vhisper to re-authorize
# Note: Microphone permission is tied to Bundle ID, no need to reset

tccutil reset Accessibility com.vimo-ai.VhisperNative

echo "✅ Accessibility permission reset. Please restart Vhisper and authorize again."
