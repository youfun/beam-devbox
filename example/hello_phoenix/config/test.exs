import Config

config :hello_phoenix, HelloPhoenix.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "hello_phoenix_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :hello_phoenix, HelloPhoenixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_for_testing_only",
  server: false

config :hello_phoenix, HelloPhoenix.Mailer, adapter: Swoosh.Adapters.Test

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
