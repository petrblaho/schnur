defmodule SchnurWeb.PageController do
  use SchnurWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
