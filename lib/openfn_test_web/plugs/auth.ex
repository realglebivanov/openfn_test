defmodule OpenfnTestWeb.Plugs.Auth do
  @moduledoc """
  Authenticates the request with the `Authorization: Bearer <token>` header and assigns the
  authenticated principal to `:current_user`. Halts with 401 (or 503 when the identity provider
  or the revocation store can't be reached) otherwise.
  """

  import Plug.Conn

  alias OpenfnTest.Auth
  alias OpenfnTestWeb.ErrorResponse

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, principal} <- Auth.authenticate(token) do
      assign(conn, :current_user, principal)
    else
      {:error, reason} -> ErrorResponse.send_error(conn, reason)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [] ->
        {:error, :missing_token}

      [header] ->
        case String.split(header, " ", parts: 2, trim: true) do
          [scheme, token] when token != "" ->
            if String.downcase(scheme) == "bearer",
              do: {:ok, String.trim(token)},
              else: {:error, :malformed_authorization_header}

          _ ->
            {:error, :malformed_authorization_header}
        end

      _many ->
        {:error, :malformed_authorization_header}
    end
  end
end
