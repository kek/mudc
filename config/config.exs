# Mudc configuration

import Config

# Configure logger:
# - Disable the default console handler (prevents TUI corruption)
# - Our custom LogHandler captures logs to a buffer
config :logger, :default_handler, false

# Set log level
config :logger, level: :debug

# Import environment-specific config (dev, prod, test)
# These can override settings above
import_config "#{config_env()}.exs"
