defmodule GakugoWeb.PageController do
  use GakugoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
