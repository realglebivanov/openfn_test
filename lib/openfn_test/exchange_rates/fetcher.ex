defmodule OpenfnTest.ExchangeRates.Fetcher do
  @moduledoc """
  Periodically fetches exchange rates into the `OpenfnTest.ExchangeRates` cache.

  Owns the `:ets` table: every successful fetch inserts a new snapshot and prunes the ones
  older than `:retention` (the latest snapshot is always kept).

  ## Options

    * `:name` - process name, defaults to `#{inspect(__MODULE__)}`
    * `:table` - ets table name, defaults to `OpenfnTest.ExchangeRates.table/0`
    * `:fetch` - zero-arity function returning `{:ok, snapshot} | {:error, reason}`,
      defaults to `OpenfnTest.ExchangeRates.Client.fetch_latest/0`
    * `:fetch_interval` - milliseconds between fetches
    * `:retention` - milliseconds to keep old snapshots for
  """
  use GenServer

  require Logger

  alias OpenfnTest.ExchangeRates
  alias OpenfnTest.ExchangeRates.{Client, Snapshot}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Fetches the rates right away and reschedules the next periodic fetch.
  """
  def refresh(server \\ __MODULE__), do: GenServer.call(server, :refresh, :infinity)

  @impl true
  def init(opts) do
    state = %{
      table: ExchangeRates.create_table(Keyword.get(opts, :table, ExchangeRates.table())),
      fetch: Keyword.get(opts, :fetch, &Client.fetch_latest/0),
      fetch_interval: Keyword.get_lazy(opts, :fetch_interval, fn -> config(:fetch_interval) end),
      retention: Keyword.get_lazy(opts, :retention, fn -> config(:retention) end),
      timer: nil
    }

    {:ok, state, {:continue, :fetch}}
  end

  @impl true
  def handle_continue(:fetch, state) do
    {_result, state} = fetch_and_schedule(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:fetch, state) do
    {_result, state} = fetch_and_schedule(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    {result, state} = fetch_and_schedule(state)
    {:reply, result, state}
  end

  defp fetch_and_schedule(state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    result = fetch(state)
    {result, %{state | timer: Process.send_after(self(), :fetch, state.fetch_interval)}}
  end

  defp fetch(state) do
    case state.fetch.() do
      {:ok, %Snapshot{} = snapshot} ->
        :ok = ExchangeRates.put(state.table, snapshot)
        cutoff = DateTime.add(snapshot.fetched_at, -state.retention, :millisecond)
        ExchangeRates.prune(state.table, cutoff)
        :ok

      {:error, reason} = error ->
        Logger.warning("Failed to refresh exchange rates: #{inspect(reason)}")
        error
    end
  end

  defp config(key), do: ExchangeRates.config(key)
end
