defmodule OpenfnTestWeb.ErrorResponse do
  @moduledoc """
  Turns error reasons into JSON error responses. Every error is logged as a warning.

  Error bodies look like:

      {"error": {"code": "account_not_found", "message": "..."}}
  """

  import Plug.Conn

  require Logger

  alias OpenfnTest.ExchangeRates

  @auth_retry_after_seconds 5

  @spec send_error(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def send_error(conn, reason) do
    {status, code, message, extra} = describe(reason)

    Logger.warning(
      "#{conn.method} #{conn.request_path} failed with #{status} #{code}: #{inspect(summarize(reason))}"
    )

    conn
    |> merge_resp_headers(headers(status, reason))
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: Map.merge(%{code: code, message: message}, extra)})
    |> halt()
  end

  defp describe(:parse_error),
    do: {400, "parse_error", "Request body must be a JSON object.", %{}}

  defp describe({:validation_error, details}),
    do: {422, "validation_error", "Request body is invalid.", %{details: details}}

  defp describe(:invalid_currency),
    do: {422, "invalid_currency", "Target currency is not supported.", %{}}

  defp describe(reason) when reason in [:unavailable, :stale],
    do: {503, "exchange_rates_unavailable", "Exchange rates are temporarily unavailable.", %{}}

  defp describe(:account_not_found),
    do: {404, "account_not_found", "No account found for the authenticated user.", %{}}

  defp describe(:missing_token),
    do: {401, "unauthorized", "Missing bearer token.", %{}}

  defp describe(:malformed_authorization_header),
    do: {401, "unauthorized", "Authorization header must be \"Bearer <token>\".", %{}}

  defp describe(:token_revoked),
    do: {401, "unauthorized", "Token has been revoked.", %{}}

  defp describe({:invalid_token, _reason}),
    do: {401, "unauthorized", "Token is invalid or expired.", %{}}

  defp describe(reason)
       when reason == :provider_not_ready or
              (is_tuple(reason) and elem(reason, 0) == :revocation_store_unavailable),
       do: {503, "auth_unavailable", "Authentication is temporarily unavailable.", %{}}

  defp headers(401, _reason), do: [{"www-authenticate", ~s(Bearer realm="api")}]

  defp headers(503, reason) when reason in [:unavailable, :stale],
    do: [{"retry-after", Integer.to_string(ExchangeRates.retry_after_seconds())}]

  defp headers(503, _reason), do: [{"retry-after", Integer.to_string(@auth_retry_after_seconds)}]
  defp headers(_status, _reason), do: []

  # Keep token claims out of the logs.
  defp summarize({:invalid_token, {:missing_claim, claim, _claims}}),
    do: {:invalid_token, {:missing_claim, claim}}

  defp summarize({:invalid_token, {:none_alg_used, _}}), do: {:invalid_token, :none_alg_used}
  defp summarize(reason), do: reason
end
