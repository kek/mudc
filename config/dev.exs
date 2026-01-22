# Development configuration

import Config

# In development, suppress log output to console to keep TUI clean
# Logs go nowhere by default (backends: [] set in config.exs)
# To enable file logging for debugging, add:
# config :logger, backends: [{LoggerFileBackend, :file_log}]
# config :logger, :file_log, path: "mudc.log", level: :debug
