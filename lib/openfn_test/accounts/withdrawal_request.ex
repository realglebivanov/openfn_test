defmodule OpenfnTest.Accounts.WithdrawalRequest do
  @moduledoc """
  A validated withdrawal request.

  The incoming JSON body is validated against a strict JSON schema (no unknown keys, all keys
  required) and only then turned into the struct.
  """

  @enforce_keys [:amount_usd, :target_currency]
  defstruct @enforce_keys

  @type t :: %__MODULE__{amount_usd: Decimal.t(), target_currency: String.t()}

  @type validation_error :: %{path: String.t(), message: String.t()}

  @schema ExJsonSchema.Schema.resolve(%{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["amount", "target_currency"],
            "properties" => %{
              "amount" => %{
                "description" =>
                  "Amount in USD as a decimal string with at most 2 fraction digits",
                "type" => "string",
                "pattern" => "^(0|[1-9][0-9]*)(\\.[0-9]{1,2})?$"
              },
              "target_currency" => %{
                "description" => "ISO 4217 currency code",
                "type" => "string",
                "pattern" => "^[A-Z]{3}$"
              }
            }
          })

  @doc """
  Parses decoded request params into a `t:t/0`.

  Returns `{:error, :parse_error}` when the body is not a JSON object and
  `{:error, {:validation_error, errors}}` when it does not match the schema.
  """
  @spec parse(term()) ::
          {:ok, t()} | {:error, :parse_error} | {:error, {:validation_error, [validation_error]}}
  def parse(%{"_json" => _}), do: {:error, :parse_error}

  def parse(%{} = params) do
    with :ok <- validate_schema(params),
         {:ok, amount} <- parse_amount(params["amount"]) do
      {:ok, %__MODULE__{amount_usd: amount, target_currency: params["target_currency"]}}
    end
  end

  def parse(_params), do: {:error, :parse_error}

  defp validate_schema(params) do
    case ExJsonSchema.Validator.validate(@schema, params) do
      :ok ->
        :ok

      {:error, errors} ->
        {:error,
         {:validation_error, Enum.map(errors, fn {message, path} -> error(path, message) end)}}
    end
  end

  # Decimal raises when the amount, padded to cents, has more digits than its context precision
  # (34 by default) can hold.
  defp parse_amount(amount) do
    amount = amount |> Decimal.new() |> Decimal.round(2)

    if Decimal.gt?(amount, 0) do
      {:ok, amount}
    else
      {:error, {:validation_error, [error("#/amount", "Must be greater than 0.")]}}
    end
  rescue
    Decimal.Error ->
      max_digits = Decimal.Context.get().precision - 2

      {:error,
       {:validation_error, [error("#/amount", "Must have at most #{max_digits} integer digits.")]}}
  end

  defp error(path, message), do: %{path: path, message: message}
end
