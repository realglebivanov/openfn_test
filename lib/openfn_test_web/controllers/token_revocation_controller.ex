defmodule OpenfnTestWeb.TokenRevocationController do
  @moduledoc """
  Revokes an access token until it expires: `POST /api/revoke {"token": "<access token>"}`.

  Possessing a valid token is what authorises revoking it, so this route doesn't go through
  the auth plug.
  """
  use OpenfnTestWeb, :controller

  alias OpenfnTest.Auth

  action_fallback OpenfnTestWeb.FallbackController

  def create(conn, %{"token" => token}) when is_binary(token) and token != "" do
    with :ok <- Auth.revoke(token) do
      json(conn, %{revoked: true})
    end
  end

  def create(_conn, _params) do
    {:error, {:validation_error, [%{path: "#/token", message: "Required non-empty string."}]}}
  end
end
