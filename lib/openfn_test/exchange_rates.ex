defmodule OpenfnTest.ExchangeRates do
  @moduledoc """
  Read side of the exchange rate cache.

  Snapshots are kept in an `:ets` ordered set keyed by their fetch time (in microseconds), so the
  latest snapshot is always the last key. The table is owned and written to by
  `OpenfnTest.ExchangeRates.Fetcher`; any process can read from it.

  A snapshot older than `:max_age` is considered stale and is never used.
  """

  alias OpenfnTest.ExchangeRates.{Rate, Snapshot}

  @table :exchange_rates

  @type error :: :unavailable | :stale
  @type opts :: [table: atom(), max_age: non_neg_integer(), now: DateTime.t()]

  def table, do: @table

  @doc false
  def create_table(table \\ @table) do
    :ets.new(table, [:ordered_set, :named_table, :protected, read_concurrency: true])
  end

  @doc false
  def put(table \\ @table, %Snapshot{fetched_at: fetched_at} = snapshot) do
    true = :ets.insert(table, {key(fetched_at), snapshot})
    :ok
  end

  @doc false
  # Deletes the snapshots fetched before `cutoff`, always keeping the latest one.
  def prune(table \\ @table, %DateTime{} = cutoff) do
    case :ets.last(table) do
      :"$end_of_table" ->
        0

      last ->
        cutoff = min(key(cutoff), last)
        :ets.select_delete(table, [{{:"$1", :_}, [{:<, :"$1", cutoff}], [true]}])
    end
  end

  @doc """
  Returns the latest snapshot unless it is missing or stale.
  """
  @spec latest(opts()) :: {:ok, Snapshot.t()} | {:error, error()}
  def latest(opts \\ []) do
    table = Keyword.get(opts, :table, @table)
    max_age = Keyword.get_lazy(opts, :max_age, fn -> config(:max_age) end)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with {:ok, snapshot} <- last_snapshot(table) do
      if DateTime.before?(snapshot.fetched_at, DateTime.add(now, -max_age, :millisecond)) do
        {:error, :stale}
      else
        {:ok, snapshot}
      end
    end
  end

  @doc """
  Returns the latest USD to `currency` exchange rate.
  """
  @spec get_rate(String.t(), opts()) :: {:ok, Rate.t()} | {:error, error() | :invalid_currency}
  def get_rate(currency, opts \\ []) do
    with {:ok, snapshot} <- latest(opts) do
      case Map.fetch(snapshot.rates, currency) do
        {:ok, rate} ->
          {:ok, %Rate{currency: currency, rate: rate, fetched_at: snapshot.fetched_at}}

        :error ->
          {:error, :invalid_currency}
      end
    end
  end

  @doc """
  How long clients should wait before retrying when no fresh rates are available.
  """
  def retry_after_seconds, do: max(div(config(:fetch_interval), 1000), 1)

  @doc false
  def config(key), do: Application.fetch_env!(:openfn_test, __MODULE__) |> Keyword.fetch!(key)

  defp last_snapshot(table) do
    with tid when tid != :undefined <- :ets.whereis(table),
         key when key != :"$end_of_table" <- :ets.last(table) do
      case :ets.lookup(table, key) do
        [{^key, snapshot}] -> {:ok, snapshot}
        # Pruned between `last` and `lookup`, so a newer snapshot exists.
        [] -> last_snapshot(table)
      end
    else
      _ -> {:error, :unavailable}
    end
  end

  defp key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
end
