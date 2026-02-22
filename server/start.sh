#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Install dependencies if needed
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
else
    source venv/bin/activate
fi

# Start agent as daemon
echo "Starting agent daemon..."
nohup python3 agent.py > agent.log 2>&1 &
AGENT_PID=$!
echo $AGENT_PID > agent.pid
echo "Agent started with PID $AGENT_PID"
echo "Logs: $SCRIPT_DIR/agent.log"
echo "To stop: kill \$(cat $SCRIPT_DIR/agent.pid)"