defmodule Schnur.Schema do
  @moduledoc """
  Base schema conventions for all Schnur Ecto schemas.

  Use this in place of `use Ecto.Schema`. It configures:

    * UUIDv7 primary keys (`Uniq.UUID`, `version: 7`) — time-ordered IDs that
      double as a chronological ordering key (see core architecture spec).
    * UUID foreign keys, so associations line up with the UUIDv7 primary keys.
    * `:utc_datetime` timestamps, matching the project's generator config.

  ## Example

      defmodule Schnur.Campaigns.Game do
        use Schnur.Schema

        schema "games" do
          field :name, :string
          timestamps()
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
      @foreign_key_type Uniq.UUID
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
