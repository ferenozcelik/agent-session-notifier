#!/bin/bash
# Double-click: builds SessionNotifier, installs it to /Applications and launches it.
cd "$(dirname "$0")"
./build.sh --install && echo && echo "Done. You can close this window."
