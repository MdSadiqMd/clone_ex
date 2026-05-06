defmodule CloneEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # HTTP/2 connection pool for GitHub API
      {Finch,
       name: CloneEx.Finch,
       pools: %{
         "https://api.github.com" => [
           size: 10,
           count: 1,
           protocols: [:http2]
         ]
       }},

      # Supervised task runner for git clone subprocesses.
      # Ensures clean shutdown: all running clones are terminated when the
      # application stops, preventing orphaned `git` OS processes.
      {Task.Supervisor, name: CloneEx.TaskSupervisor},

      # Telemetry event handler (attaches to :telemetry on init)
      CloneEx.Telemetry
    ]

    opts = [strategy: :one_for_one, name: CloneEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
