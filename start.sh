#!/usr/bin/env bash
# Start Mudc with remote REPL support
#
# This script starts the Mudc MUD client with distributed Erlang enabled,
# allowing you to connect from a remote IEx session for debugging.
#
# Usage:
#   ./start.sh              # Start with default node name (mudc)
#   ./start.sh mynode       # Start with custom node name
#
# To connect remotely from another terminal:
#   iex --sname debug --remsh mudc@$(hostname -s)
#
# Or if you used a custom node name:
#   iex --sname debug --remsh mynode@$(hostname -s)

NODE_NAME=${1:-mudc}
HOSTNAME=$(hostname -s)
COOKIE="mudc_secret_cookie"

echo "Starting Mudc MUD Client..."
echo "Node name: ${NODE_NAME}@${HOSTNAME}"
echo "Cookie: ${COOKIE}"
echo ""
echo "To connect remotely, run in another terminal:"
echo "  iex --sname debug --remsh ${NODE_NAME}@${HOSTNAME}"
echo ""

# Set the cookie and start with a named node
elixir --sname ${NODE_NAME} --cookie ${COOKIE} -S mix run -e "Mudc.run()"
