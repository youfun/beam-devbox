defmodule HelloPhoenixWeb.ErrorHTML do
  use HelloPhoenixWeb, :html

  def render("404.html", _assigns) do
    "<h1>Page not found</h1>"
  end

  def render("500.html", _assigns) do
    "<h1>Internal server error</h1>"
  end

  def render(_template, _assigns) do
    "<h1>Error</h1>"
  end
end
