import Config

# Tesla HTTP adapter — use Finch for HTTP/2 multiplexing + connection pooling
config :tesla,
  adapter: {Tesla.Adapter.Finch, name: CloneEx.Finch},
  disable_deprecated_builder_warning: true

# Logger formatting
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :repo]

# Broadway config storage — persistent_term for static pipeline definitions
config :broadway,
  config_storage: :persistent_term

# Import environment-specific config
import_config "#{config_env()}.exs"
