defmodule Schnur.Repo do
  use Ecto.Repo,
    otp_app: :schnur,
    adapter: Ecto.Adapters.SQLite3
end
