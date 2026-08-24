defmodule Schnur.ObanConfigTest do
  use ExUnit.Case, async: true

  test "the scribe queue is configured at concurrency 1" do
    config = Application.fetch_env!(:schnur, Oban)
    assert Keyword.fetch!(config, :queues) == [scribe: 1]
  end

  test "oban uses the Schnur repo" do
    config = Application.fetch_env!(:schnur, Oban)
    assert Keyword.fetch!(config, :repo) == Schnur.Repo
  end

  test "oban runs in manual testing mode" do
    config = Application.fetch_env!(:schnur, Oban)
    assert Keyword.fetch!(config, :testing) == :manual
  end

  test "the Oban instance is running (started by the supervision tree)" do
    # `Oban.config/0` looks the running instance up in Oban's Registry (in-memory,
    # no DB) and raises if no instance named `Oban` is supervised. So a non-raising
    # call is a real assertion that Oban is wired into the app's supervision tree —
    # stronger than inspecting the supervisor child list, and safe from a plain
    # `ExUnit.Case` (no Ecto sandbox needed). Under `testing: :manual` Oban's
    # supervisor still starts (it only sets queues: [] and plugins: []), so the
    # instance is registered. We assert the struct type only, not internal field
    # shapes, to avoid coupling the test to Oban's private config layout.
    assert %Oban.Config{} = Oban.config()
  end
end
