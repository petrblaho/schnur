defmodule Schnur.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  # For a fresh install, call up/0 and down/0 with NO version pin so Oban
  # migrates to its own latest schema version. Pinning a version here would
  # freeze the schema below the library's current version and silently omit
  # later migrations. Per Oban.Migration docs.
  def up do
    Oban.Migration.up()
  end

  def down do
    Oban.Migration.down()
  end
end
