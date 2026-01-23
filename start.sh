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
COOKIE_FILE="$HOME/.config/mudc/.erlang.cookie"

# Generate cookie if it doesn't exist or read existing one
if [ ! -f "$COOKIE_FILE" ]; then
  echo "Generating secure cookie..."
  mkdir -p "$(dirname "$COOKIE_FILE")"
  # Generate 32 bytes of random data, base64 encode it
  COOKIE=$(openssl rand -base64 32 | tr -d '=')
  echo "$COOKIE" > "$COOKIE_FILE"
  chmod 600 "$COOKIE_FILE"
else
  COOKIE=$(cat "$COOKIE_FILE")
fi

echo "Starting Mudc MUD Client..."
echo "Node name: ${NODE_NAME}@${HOSTNAME}"
echo "Cookie: [secure - stored in ~/.config/mudc/.erlang.cookie]"
echo ""
echo "To connect remotely, run in another terminal:"
echo "  iex --sname debug --remsh ${NODE_NAME}@${HOSTNAME}"
echo ""

# Set the cookie and start with a named node
elixir --sname ${NODE_NAME} --cookie ${COOKIE} -S mix run -e "Mudc.run()"
