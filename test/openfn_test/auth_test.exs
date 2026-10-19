defmodule OpenfnTest.AuthTest do
  use ExUnit.Case, async: true

  import Mox

  alias OpenfnTest.Auth
  alias OpenfnTest.Auth.{RevocationStoreMock, TokenVerifierMock}

  setup :verify_on_exit!

  defp claims(overrides \\ %{}) do
    Map.merge(
      %{"sub" => "user-1", "jti" => "jti-1", "exp" => System.system_time(:second) + 300},
      overrides
    )
  end

  describe "authenticate/1" do
    test "accepts a verified, non revoked token" do
      claims = claims()
      expect(TokenVerifierMock, :verify, fn "token" -> {:ok, claims} end)
      expect(RevocationStoreMock, :revoked?, fn "jti-1" -> {:ok, false} end)

      assert {:ok, %{user_id: "user-1", claims: ^claims}} = Auth.authenticate("token")
    end

    test "rejects revoked tokens" do
      expect(TokenVerifierMock, :verify, fn _ -> {:ok, claims()} end)
      expect(RevocationStoreMock, :revoked?, fn _ -> {:ok, true} end)

      assert {:error, :token_revoked} = Auth.authenticate("token")
    end

    test "uses a digest of the token when it has no jti" do
      digest = :sha256 |> :crypto.hash("token") |> Base.encode16(case: :lower)
      expect(TokenVerifierMock, :verify, fn _ -> {:ok, Map.delete(claims(), "jti")} end)
      expect(RevocationStoreMock, :revoked?, fn ^digest -> {:ok, false} end)

      assert {:ok, _} = Auth.authenticate("token")
    end

    test "rejects tokens that fail verification without checking revocation" do
      expect(TokenVerifierMock, :verify, fn _ -> {:error, :token_expired} end)

      assert {:error, {:invalid_token, :token_expired}} = Auth.authenticate("token")
    end

    test "reports an unavailable identity provider" do
      expect(TokenVerifierMock, :verify, fn _ -> {:error, :provider_not_ready} end)

      assert {:error, :provider_not_ready} = Auth.authenticate("token")
    end

    test "fails closed when the revocation store is down" do
      expect(TokenVerifierMock, :verify, fn _ -> {:ok, claims()} end)
      expect(RevocationStoreMock, :revoked?, fn _ -> {:error, :closed} end)

      assert {:error, {:revocation_store_unavailable, :closed}} = Auth.authenticate("token")
    end
  end

  describe "revoke/1" do
    test "stores the token id until the token expires" do
      exp = System.system_time(:second) + 300
      expect(TokenVerifierMock, :verify, fn _ -> {:ok, claims(%{"exp" => exp})} end)

      expect(RevocationStoreMock, :revoke, fn "jti-1", ttl ->
        assert ttl in 299..300
        :ok
      end)

      assert :ok = Auth.revoke("token")
    end

    test "rejects invalid tokens" do
      expect(TokenVerifierMock, :verify, fn _ -> {:error, :bad_signature} end)

      assert {:error, {:invalid_token, :bad_signature}} = Auth.revoke("token")
    end
  end
end
