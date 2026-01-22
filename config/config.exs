# Mudc configuration

import Config

# Configure logger:
# - Disable the default console handler (prevents TUI corruption)
# - Our custom LogHandler captures logs to a buffer viewable with F8
config :logger, :default_handler, false

# Set log level - debug shows all messages in the log viewer
config :logger, level: :debug

# Import environment-specific config (dev, prod, test)
# These can override settings above
import_config "#{config_env()}.exs"
