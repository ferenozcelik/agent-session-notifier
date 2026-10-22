#!/bin/bash
# Double-click: builds AgentSessionNotifier, installs it to /Applications and launches it.
cd "$(dirname "$0")"
./build.sh --install && echo && echo "Done. You can close this window."
