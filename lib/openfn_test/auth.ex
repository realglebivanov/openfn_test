defmodule OpenfnTest.Auth do
  @moduledoc """
  Bearer token authentication.

  A token is accepted when it is verified by the configured `OpenfnTest.Auth.TokenVerifier`
  and has not been revoked in the configured `OpenfnTest.Auth.RevocationStore`.
  """

  @type principal :: %{user_id: String.t(), claims: map()}

  @type error ::
          :provider_not_ready
          | :token_revoked
          | {:invalid_token, term()}
          | {:revocation_store_unavailable, term()}

  @spec authenticate(String.t()) :: {:ok, principal()} | {:error, error()}
  def authenticate(token) do
    with {:ok, claims} <- verify(token),
         {:ok, false} <- revoked?(revocation_key(token, claims)) do
      {:ok, %{user_id: Map.fetch!(claims, "sub"), claims: claims}}
    else
      {:ok, true} -> {:error, :token_revoked}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Revokes a valid token until it expires.
  """
  @spec revoke(String.t()) :: :ok | {:error, error()}
  def revoke(token) do
    with {:ok, claims} <- verify(token) do
      case Map.fetch!(claims, "exp") - System.system_time(:second) do
        ttl when ttl > 0 -> store_revocation(revocation_key(token, claims), ttl)
        _expired -> :ok
      end
    end
  end

  defp verify(token) do
    case token_verifier().verify(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, :provider_not_ready} -> {:error, :provider_not_ready}
      {:error, reason} -> {:error, {:invalid_token, reason}}
    end
  end

  defp revoked?(key) do
    case revocation_store().revoked?(key) do
      {:ok, revoked?} -> {:ok, revoked?}
      {:error, reason} -> {:error, {:revocation_store_unavailable, reason}}
    end
  end

  defp store_revocation(key, ttl) do
    case revocation_store().revoke(key, ttl) do
      :ok -> :ok
      {:error, reason} -> {:error, {:revocation_store_unavailable, reason}}
    end
  end

  # Prefer the token id, fall back to a digest of the token itself.
  defp revocation_key(_token, %{"jti" => jti}) when is_binary(jti) and jti != "", do: jti

  defp revocation_key(token, _claims),
    do: :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)

  defp token_verifier, do: Application.fetch_env!(:openfn_test, :token_verifier)
  defp revocation_store, do: Application.fetch_env!(:openfn_test, :revocation_store)
end
