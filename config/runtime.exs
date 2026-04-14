import Config

# Runtime config — reads environment variables at boot time (not compile time)
config :clone_ex,
  github_token: System.get_env("GITHUB_TOKEN")
