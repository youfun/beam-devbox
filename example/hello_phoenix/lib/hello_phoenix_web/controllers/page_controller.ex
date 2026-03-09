defmodule HelloPhoenixWeb.PageController do
  use HelloPhoenixWeb, :controller

  alias ExAws.S3

  def home(conn, _params) do
    render(conn, :home)
  end

  def upload_form(conn, _params) do
    render(conn, :upload)
  end

  def do_upload(conn, %{"file" => file}) do
    bucket = System.get_env("MINIO_BUCKET", "uploads")
    filename = "#{System.system_time(:millisecond)}-#{file.filename}"

    case upload_to_s3(file.path, bucket, filename) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "File uploaded successfully!")
        |> redirect(to: ~p"/files")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Upload failed: #{inspect(reason)}")
        |> redirect(to: ~p"/upload")
    end
  end

  def list_files(conn, _params) do
    bucket = System.get_env("MINIO_BUCKET", "uploads")

    files =
      case list_s3_objects(bucket) do
        {:ok, objects} -> objects
        {:error, _} -> []
      end

    render(conn, :files, files: files)
  end

  defp upload_to_s3(local_path, bucket, key) do
    local_path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket, key)
    |> ExAws.request()
  end

  defp list_s3_objects(bucket) do
    case S3.list_objects(bucket) |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} -> {:ok, contents}
      error -> error
    end
  end
end