defmodule HelloPhoenixWeb.HealthController do
  use HelloPhoenixWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      services: %{
        postgres: check_postgres(),
        minio: check_minio()
      }
    })
  end

  defp check_postgres do
    try do
      HelloPhoenix.Repo.query!("SELECT 1")
      :ok
    rescue
      _ -> :error
    end
  end

  defp check_minio do
    # Simple check - in production you'd check S3 connectivity
    :ok
  end
end
