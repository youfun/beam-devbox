defmodule HelloPhoenixWeb.Router do
  use HelloPhoenixWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HelloPhoenixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HelloPhoenixWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/upload", PageController, :upload_form
    post "/upload", PageController, :do_upload
    get "/files", PageController, :list_files
  end

  scope "/api", HelloPhoenixWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end
end
