defmodule OpenfnTest.ExchangeRates.ApiSpec do
  @url "https://api.frankfurter.dev/v2/openapi.json"

  @moduledoc """
  The [Frankfurter](https://frankfurter.dev) OpenAPI spec, fetched from `#{@url}` and decoded at
  compile time. Recompile this module (`mix compile --force`) to pick up a newer spec.

  The spec is written in OpenAPI 3.1, see `OpenfnTest.ExchangeRates.ApiSpec.Downgrade` for how it
  is adapted to `OpenApiSpex`.
  """

  alias OpenApiSpex.{Cast, OpenApi}
  alias OpenfnTest.ExchangeRates.ApiSpec.Downgrade

  {:ok, _} = Application.ensure_all_started(:req)

  @spec_ [url: @url, decode_body: false, retry: :transient]
         |> Req.get!()
         |> then(fn %Req.Response{status: 200, body: body} -> body end)
         |> Jason.decode!()
         |> Downgrade.downgrade()
         |> OpenApi.Decode.decode()

  @spec spec() :: OpenApi.t()
  def spec, do: @spec_

  @doc """
  Casts and validates a decoded `getRates` JSON response against the spec.

  Error messages include the path of the offending value.
  """
  @spec cast_rates(term()) :: {:ok, [map()]} | {:error, [String.t()]}
  def cast_rates(value) do
    schema = @spec_.paths["/rates"].get.responses["200"].content["application/json"].schema

    case OpenApiSpex.cast_value(value, schema, @spec_) do
      {:ok, rates} -> {:ok, rates}
      {:error, errors} -> {:error, Enum.map(errors, &Cast.Error.message_with_path/1)}
    end
  end
end
