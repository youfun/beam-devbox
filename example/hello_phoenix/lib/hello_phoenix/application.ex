defmodule HelloPhoenix.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HelloPhoenixWeb.Telemetry,
      HelloPhoenix.Repo,
      {Ecto.Migrator, repos: Application.fetch_env!(:hello_phoenix, :ecto_repos)},
      {Phoenix.PubSub, name: HelloPhoenix.PubSub},
      {Finch, name: HelloPhoenix.Finch},
      HelloPhoenixWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: HelloPhoenix.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HelloPhoenixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
