defmodule OpenfnTest.ExchangeRates.Rate do
  @moduledoc """
  A USD to `currency` exchange rate taken from a cached snapshot.
  """

  @enforce_keys [:currency, :rate, :fetched_at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{currency: String.t(), rate: Decimal.t(), fetched_at: DateTime.t()}
end
