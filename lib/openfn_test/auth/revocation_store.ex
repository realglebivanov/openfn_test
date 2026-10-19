defmodule OpenfnTest.Auth.RevocationStore do
  @moduledoc """
  Keeps track of revoked tokens. Entries expire after `ttl` seconds, i.e. once the token would
  have expired on its own anyway.
  """

  @callback revoke(key :: String.t(), ttl :: pos_integer()) :: :ok | {:error, term()}
  @callback revoked?(key :: String.t()) :: {:ok, boolean()} | {:error, term()}
end
