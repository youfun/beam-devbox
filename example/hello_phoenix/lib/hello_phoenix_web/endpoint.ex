defmodule HelloPhoenixWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hello_phoenix

  plug Plug.Static,
    at: "/",
    from: :hello_phoenix,
    gzip: false,
    only: HelloPhoenixWeb.static_paths()

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :hello_phoenix
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, store: :cookie, key: "_hello_phoenix_key", signing_salt: "your_signing_salt"
  plug HelloPhoenixWeb.Router
end
