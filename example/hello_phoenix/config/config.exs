import Config

config :hello_phoenix,
  ecto_repos: [HelloPhoenix.Repo],
  generators: [timestamp_type: :utc_datetime]

config :hello_phoenix, HelloPhoenixWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HelloPhoenixWeb.ErrorHTML, json: HelloPhoenixWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HelloPhoenix.PubSub,
  live_view: [signing_salt: "your_signing_salt_here"]

config :hello_phoenix, HelloPhoenix.Mailer, adapter: Swoosh.Adapters.Local

config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure ExAWS for MinIO
config :ex_aws,
  access_key_id: System.get_env("MINIO_ROOT_USER", "minioadmin"),
  secret_access_key: System.get_env("MINIO_ROOT_PASSWORD", "minioadmin"),
  region: "us-east-1"

config :ex_aws, :s3,
  scheme: "http://",
  host: System.get_env("MINIO_HOST", "localhost"),
  port: String.to_integer(System.get_env("MINIO_PORT", "9000")),
  region: "us-east-1"

import_config "#{config_env()}.exs"
