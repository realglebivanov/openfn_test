defmodule OpenfnTest.ExchangeRatesTest do
  use ExUnit.Case, async: true

  import OpenfnTest.Fixtures

  alias OpenfnTest.ExchangeRates
  alias OpenfnTest.ExchangeRates.Rate

  setup do
    table = unique_table_name()
    ExchangeRates.create_table(table)
    %{table: table, opts: [table: table, max_age: :timer.minutes(10)]}
  end

  test "is unavailable without a table" do
    assert {:error, :unavailable} = ExchangeRates.latest(table: unique_table_name())
  end

  test "is unavailable while empty", %{opts: opts} do
    assert {:error, :unavailable} = ExchangeRates.latest(opts)
    assert {:error, :unavailable} = ExchangeRates.get_rate("EUR", opts)
  end

  test "returns the most recently fetched snapshot", %{table: table, opts: opts} do
    now = DateTime.utc_now()
    older = snapshot_fixture(fetched_at: DateTime.add(now, -60), rates: %{"EUR" => "0.90"})
    newer = snapshot_fixture(fetched_at: now, rates: %{"EUR" => "0.92"})

    :ok = ExchangeRates.put(table, newer)
    :ok = ExchangeRates.put(table, older)

    assert {:ok, ^newer} = ExchangeRates.latest(opts)

    assert {:ok, %Rate{currency: "EUR", rate: rate, fetched_at: ^now}} =
             ExchangeRates.get_rate("EUR", opts)

    assert Decimal.equal?(rate, "0.92")
  end

  test "rejects unknown currencies", %{table: table, opts: opts} do
    :ok = ExchangeRates.put(table, snapshot_fixture())
    assert {:error, :invalid_currency} = ExchangeRates.get_rate("XXX", opts)
  end

  test "rejects stale snapshots", %{table: table, opts: opts} do
    now = DateTime.utc_now()
    :ok = ExchangeRates.put(table, snapshot_fixture(fetched_at: DateTime.add(now, -11, :minute)))

    assert {:error, :stale} = ExchangeRates.latest(opts)
    assert {:error, :stale} = ExchangeRates.get_rate("EUR", opts)
    assert {:ok, _} = ExchangeRates.latest(Keyword.put(opts, :max_age, :timer.minutes(12)))
  end

  test "prune/2 deletes old snapshots but keeps the latest", %{table: table, opts: opts} do
    now = DateTime.utc_now()

    for minutes <- [30, 20, 10] do
      :ok =
        ExchangeRates.put(
          table,
          snapshot_fixture(fetched_at: DateTime.add(now, -minutes, :minute))
        )
    end

    assert ExchangeRates.prune(table, DateTime.add(now, -15, :minute)) == 2
    assert :ets.info(table, :size) == 1

    # Even if the cutoff is past the latest snapshot.
    assert ExchangeRates.prune(table, now) == 0
    assert {:ok, _} = ExchangeRates.latest(Keyword.put(opts, :max_age, :timer.hours(1)))
  end
end
