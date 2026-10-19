defmodule OpenfnTest.ExchangeRates.FetcherTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import OpenfnTest.Fixtures

  alias OpenfnTest.ExchangeRates
  alias OpenfnTest.ExchangeRates.Fetcher

  # Each fetch returns the next of the given results.
  defp start_fetcher(table, results) do
    agent = start_supervised!({Agent, fn -> results end})

    fetch = fn ->
      Agent.get_and_update(agent, fn [result | rest] -> {result, rest} end)
    end

    start_supervised!(
      {Fetcher,
       name: :"fetcher_#{table}",
       table: table,
       fetch: fetch,
       fetch_interval: :timer.hours(1),
       retention: :timer.minutes(10)}
    )
  end

  test "fetches on start" do
    table = unique_table_name()
    snapshot = snapshot_fixture()
    pid = start_fetcher(table, [{:ok, snapshot}])

    _ = :sys.get_state(pid)
    assert {:ok, ^snapshot} = ExchangeRates.latest(table: table)
  end

  test "keeps the last snapshot when a refresh fails" do
    table = unique_table_name()
    snapshot = snapshot_fixture()
    pid = start_fetcher(table, [{:ok, snapshot}, {:error, :boom}])

    log =
      capture_log(fn ->
        assert {:error, :boom} = Fetcher.refresh(pid)
      end)

    assert log =~ "Failed to refresh exchange rates: :boom"
    assert {:ok, ^snapshot} = ExchangeRates.latest(table: table)
  end

  test "prunes snapshots older than the retention period" do
    table = unique_table_name()
    now = DateTime.utc_now()

    pid =
      start_fetcher(table, [
        {:ok, snapshot_fixture(fetched_at: DateTime.add(now, -20, :minute))},
        {:ok, snapshot_fixture(fetched_at: DateTime.add(now, -5, :minute))},
        {:ok, snapshot_fixture(fetched_at: now)}
      ])

    # The -20 minutes snapshot falls out of the retention window of the -5 minutes one.
    assert :ok = Fetcher.refresh(pid)
    assert :ets.info(table, :size) == 1

    assert :ok = Fetcher.refresh(pid)
    assert :ets.info(table, :size) == 2
    assert {:ok, %{fetched_at: ^now}} = ExchangeRates.latest(table: table)
  end

  test "the cache is unavailable until the first successful fetch" do
    table = unique_table_name()

    capture_log(fn ->
      pid = start_fetcher(table, [{:error, :boom}])
      _ = :sys.get_state(pid)
    end)

    assert {:error, :unavailable} = ExchangeRates.latest(table: table)
  end
end
