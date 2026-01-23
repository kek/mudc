# Mudc configuration

import Config

# Configure logger:
# - Disable the default console handler (prevents TUI corruption)
# - Our custom LogHandler captures logs to a buffer
config :logger, :default_handler, false

# Set log level
config :logger, level: :debug

# Distributed Erlang configuration for remote REPL access
# Start the node with: iex --sname mudc -S mix
# Connect remotely with: iex --sname debug --remsh mudc@hostname
config :mudc,
  node_name: :mudc,
  cookie: :mudc_secret_cookie

# Import environment-specific config (dev, prod, test)
# These can override settings above
import_config "#{config_env()}.exs"
