defmodule OpenfnTest.ExchangeRates.Client do
  @moduledoc """
  [Frankfurter](https://frankfurter.dev) API client.

  Fetches the latest rates for the base currency from the `getRates` operation, validating the
  response against `OpenfnTest.ExchangeRates.ApiSpec`. Retries transient failures (transport errors,
  429 and 5xx responses) with exponential backoff and jitter. Every failed attempt is logged.

  All rates are decoded straight into `Decimal`s, floats are never involved.
  """

  require Logger

  alias OpenfnTest.ExchangeRates.{ApiSpec, Snapshot}

  @defaults [
    base_url: "https://api.frankfurter.dev",
    base_currency: "USD",
    max_attempts: 3,
    backoff_base: 500,
    backoff_max: 5_000,
    receive_timeout: 5_000,
    req_options: []
  ]

  @type error ::
          {:http_status, pos_integer()}
          | {:transport_error, Exception.t()}
          | {:invalid_response, term()}

  @spec fetch_latest(keyword()) :: {:ok, Snapshot.t()} | {:error, error()}
  def fetch_latest(opts \\ []) do
    opts =
      @defaults
      |> Keyword.merge(Application.get_env(:openfn_test, __MODULE__, []))
      |> Keyword.merge(opts)

    [
      base_url: opts[:base_url],
      url: "/v2/rates",
      params: [base: opts[:base_currency]],
      receive_timeout: opts[:receive_timeout],
      decode_body: false,
      # Retries are handled below so every failed attempt gets logged the same way.
      retry: false
    ]
    |> Req.new()
    |> Req.merge(opts[:req_options])
    |> attempt(opts, 1)
  end

  defp attempt(req, opts, attempt) do
    max_attempts = opts[:max_attempts]

    case request(req, opts[:base_currency]) do
      {:ok, snapshot} ->
        {:ok, snapshot}

      {:error, reason} = error ->
        Logger.warning(
          "Exchange rate fetch attempt #{attempt}/#{max_attempts} failed: #{inspect(reason)}"
        )

        if retryable?(reason) and attempt < max_attempts do
          Process.sleep(backoff(attempt, opts))
          attempt(req, opts, attempt + 1)
        else
          error
        end
    end
  end

  defp request(req, base_currency) do
    case Req.get(req) do
      {:ok, %Req.Response{status: 200, body: body}} -> parse(body, base_currency)
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, {:transport_error, exception}}
    end
  end

  defp retryable?({:http_status, status}), do: status == 429 or status >= 500
  defp retryable?({:transport_error, _}), do: true
  defp retryable?(_reason), do: false

  defp backoff(attempt, opts) do
    delay = min(opts[:backoff_base] * 2 ** (attempt - 1), opts[:backoff_max])
    delay + :rand.uniform(div(delay, 4) + 1) - 1
  end

  @doc false
  def parse(body, base_currency) do
    with {:ok, decoded} <- decode(body),
         {:ok, records} <- cast(decoded),
         {:ok, rates} <- parse_rates(records, decoded, base_currency) do
      {:ok,
       %Snapshot{
         base: base_currency,
         # Each currency is published on its own date, the snapshot is as recent as the latest one.
         date: records |> Enum.map(& &1.date) |> Enum.max(Date),
         rates: Map.put(rates, base_currency, Decimal.new(1)),
         fetched_at: DateTime.utc_now()
       }}
    end
  end

  defp decode(body) when is_binary(body) do
    case Jason.decode(body, floats: :decimals) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, %Jason.DecodeError{}} -> {:error, {:invalid_response, :invalid_json}}
    end
  end

  defp cast(decoded) do
    case ApiSpec.cast_rates(decoded) do
      {:ok, []} -> {:error, {:invalid_response, :no_rates}}
      {:ok, records} -> {:ok, records}
      {:error, errors} -> {:error, {:invalid_response, errors}}
    end
  end

  # The spec casts rates into floats, so they are taken from the decoded body instead.
  defp parse_rates(records, decoded, base_currency) do
    records
    |> Enum.zip_with(decoded, fn record, %{"rate" => rate} -> %{record | rate: rate} end)
    |> Enum.reduce_while({:ok, %{}}, fn record, {:ok, acc} ->
      with %{base: ^base_currency, quote: currency, rate: rate} <- record,
           {:ok, rate} <- to_decimal(rate) do
        {:cont, {:ok, Map.put(acc, currency, rate)}}
      else
        _ -> {:halt, {:error, {:invalid_response, {:invalid_rate, record}}}}
      end
    end)
  end

  defp to_decimal(%Decimal{} = rate), do: {:ok, rate}
  defp to_decimal(rate) when is_integer(rate), do: {:ok, Decimal.new(rate)}
  defp to_decimal(_rate), do: :error
end
