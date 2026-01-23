#!/usr/bin/env bash
# Connect to a running Mudc instance via remote REPL
#
# This script connects to a running Mudc node using distributed Erlang,
# allowing you to inspect and debug the application without restarting it.
#
# Usage:
#   ./connect.sh              # Connect to default node (mudc@localhost)
#   ./connect.sh mynode       # Connect to custom node name
#   ./connect.sh mudc myhost  # Connect to node on specific host
#
# Prerequisites:
#   - Mudc must be running with: ./start.sh (or iex --sname mudc -S mix)
#   - Both nodes must use the same cookie

NODE_NAME=${1:-mudc}
HOSTNAME=${2:-$(hostname -s)}
COOKIE="mudc_secret_cookie"

echo "Connecting to remote Mudc REPL..."
echo "Target node: ${NODE_NAME}@${HOSTNAME}"
echo "Cookie: ${COOKIE}"
echo ""
echo "Note: Press Ctrl+C twice to disconnect (leaves Mudc running)"
echo ""

# Connect to the remote node
iex --sname debug_$(date +%s) --cookie ${COOKIE} --remsh ${NODE_NAME}@${HOSTNAME}
