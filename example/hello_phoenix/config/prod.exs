import Config

config :hello_phoenix, HelloPhoenix.Repo, pool_size: 10

config :hello_phoenix, HelloPhoenixWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info
