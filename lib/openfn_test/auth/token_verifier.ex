defmodule OpenfnTest.Auth.TokenVerifier do
  @moduledoc """
  Verifies a bearer token and returns its claims.
  """

  @callback verify(token :: String.t()) ::
              {:ok, claims :: map()} | {:error, :provider_not_ready | term()}
end
