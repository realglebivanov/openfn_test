defmodule OpenfnTest.ExchangeRates.Snapshot do
  @moduledoc """
  A dictionary of exchange rates from `base` to every currency in `rates`, as published for
  `date` and fetched at `fetched_at`.
  """

  @enforce_keys [:base, :date, :rates, :fetched_at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          base: String.t(),
          date: Date.t(),
          rates: %{String.t() => Decimal.t()},
          fetched_at: DateTime.t()
        }
end
