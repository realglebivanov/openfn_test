defmodule OpenfnTestWeb.TokenRevocationControllerTest do
  use OpenfnTestWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Mox

  alias OpenfnTest.Auth.{RevocationStoreMock, TokenVerifierMock}

  setup :verify_on_exit!

  test "revokes a valid token", %{conn: conn} do
    expect(TokenVerifierMock, :verify, fn "token" ->
      {:ok, %{"sub" => "user", "jti" => "jti-1", "exp" => System.system_time(:second) + 60}}
    end)

    expect(RevocationStoreMock, :revoke, fn "jti-1", _ttl -> :ok end)

    assert %{"revoked" => true} =
             conn |> post(~p"/api/revoke", %{token: "token"}) |> json_response(200)
  end

  test "rejects invalid tokens", %{conn: conn} do
    expect(TokenVerifierMock, :verify, fn _ -> {:error, :invalid_jwt_token} end)

    capture_log(fn ->
      assert conn |> post(~p"/api/revoke", %{token: "garbage"}) |> json_response(401)
    end)
  end

  test "requires a token", %{conn: conn} do
    capture_log(fn ->
      assert %{"error" => %{"code" => "validation_error"}} =
               conn |> post(~p"/api/revoke", %{}) |> json_response(422)
    end)
  end
end
