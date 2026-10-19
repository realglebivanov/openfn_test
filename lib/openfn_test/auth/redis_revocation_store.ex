defmodule OpenfnTest.Auth.RedisRevocationStore do
  @moduledoc """
  Redis backed revocation store. Every revoked token is a `revoked_token:<key>` entry with a TTL.
  """
  @behaviour OpenfnTest.Auth.RevocationStore

  @conn OpenfnTest.Redix
  @prefix "revoked_token:"

  def child_spec(_opts) do
    url = Application.fetch_env!(:openfn_test, :redis_url)
    Redix.child_spec({url, name: @conn})
  end

  @impl true
  def revoke(key, ttl) when is_integer(ttl) and ttl > 0 do
    case Redix.command(@conn, ["SET", @prefix <> key, "1", "EX", Integer.to_string(ttl)]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def revoked?(key) do
    case Redix.command(@conn, ["EXISTS", @prefix <> key]) do
      {:ok, count} -> {:ok, count > 0}
      {:error, reason} -> {:error, reason}
    end
  end
end
