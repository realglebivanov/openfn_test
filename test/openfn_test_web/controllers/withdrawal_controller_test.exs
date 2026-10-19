defmodule OpenfnTestWeb.WithdrawalControllerTest do
  # Not async: uses the globally named exchange rates cache.
  use OpenfnTestWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Mox
  import OpenfnTest.Fixtures

  alias OpenfnTest.Auth.{RevocationStoreMock, TokenVerifierMock}
  alias OpenfnTest.ExchangeRates.Fetcher
  alias OpenfnTest.Repo

  setup :verify_on_exit!

  setup tags do
    snapshot = Map.get(tags, :snapshot, snapshot_fixture())

    if snapshot != :none do
      pid = start_supervised!({Fetcher, fetch: fn -> {:ok, snapshot} end})
      _ = :sys.get_state(pid)
    end

    account = account_fixture(balance: "1000.00")

    stub(TokenVerifierMock, :verify, fn
      "token-" <> user_id ->
        {:ok, %{"sub" => user_id, "jti" => "jti-#{user_id}", "exp" => 2_000_000_000}}

      _ ->
        {:error, :invalid_jwt_token}
    end)

    stub(RevocationStoreMock, :revoked?, fn _ -> {:ok, false} end)

    %{account: account}
  end

  defp withdraw(conn, user_id, body) do
    body = if is_binary(body), do: body, else: Jason.encode!(body)

    conn
    |> put_req_header("authorization", "Bearer token-#{user_id}")
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/withdraw", body)
  end

  describe "POST /api/withdraw" do
    test "authorises the withdrawal", %{conn: conn, account: account} do
      conn = withdraw(conn, account.user_id, %{amount: "125.50", target_currency: "EUR"})

      assert %{
               "id" => "wd_" <> id,
               "account_id" => account_id,
               "status" => "authorised",
               "authorisation_code" => code,
               "amount_usd" => "125.50",
               "target_currency" => "EUR",
               "converted_amount" => "115.46",
               "exchange_rate" => "0.92",
               "exchange_rate_fetched_at" => _,
               "created_at" => created_at
             } = json_response(conn, 201)

      assert account_id == "acc_#{account.id}"
      assert code =~ ~r/\A[A-Za-z0-9+\/]{4}(-[A-Za-z0-9+\/]{4})+\z/

      assert code ==
               OpenfnTest.Accounts.Withdrawal.authorisation_code(%OpenfnTest.Accounts.Withdrawal{
                 id: String.to_integer(id)
               })

      assert {:ok, _, 0} = DateTime.from_iso8601(created_at)
      assert Decimal.equal?(Repo.reload!(account).balance, "1000.00")
      assert Decimal.equal?(OpenfnTest.Accounts.available_balance(account), "874.50")
    end

    test "rejects an unknown currency", %{conn: conn, account: account} do
      log =
        capture_log(fn ->
          conn = withdraw(conn, account.user_id, %{amount: "1.00", target_currency: "XXX"})
          assert %{"error" => %{"code" => "invalid_currency"}} = json_response(conn, 422)
        end)

      assert log =~ "invalid_currency"
    end

    test "rejects invalid bodies", %{conn: conn, account: account} do
      capture_log(fn ->
        conn = withdraw(conn, account.user_id, %{amount: 1, target_currency: "EUR", extra: 1})

        assert %{"error" => %{"code" => "validation_error", "details" => details}} =
                 json_response(conn, 422)

        assert Enum.any?(details, &(&1["path"] == "#/amount"))
      end)
    end

    test "rejects non-object JSON", %{conn: conn, account: account} do
      capture_log(fn ->
        conn = withdraw(conn, account.user_id, "[1, 2]")
        assert %{"error" => %{"code" => "parse_error"}} = json_response(conn, 400)
      end)
    end

    test "rejects malformed JSON", %{conn: conn, account: account} do
      log =
        capture_log(fn ->
          {400, _headers, body} =
            assert_error_sent 400, fn -> withdraw(conn, account.user_id, "{\"amount\":") end

          assert %{"error" => %{"code" => "parse_error"}} = Jason.decode!(body)
        end)

      assert log =~ "POST /api/withdraw failed with 400 parse_error"
    end

    test "returns the rejected withdrawal when it exceeds the balance", %{conn: conn} do
      account = account_fixture(balance: "10.00")

      log =
        capture_log(fn ->
          conn = withdraw(conn, account.user_id, %{amount: "10.01", target_currency: "EUR"})

          assert %{
                   "id" => "wd_" <> id,
                   "status" => "rejected",
                   "authorisation_code" => nil,
                   "amount_usd" => "10.01",
                   "converted_amount" => "9.21"
                 } = json_response(conn, 422)

          assert %{status: "rejected"} =
                   Repo.get!(OpenfnTest.Accounts.Withdrawal, String.to_integer(id))
        end)

      assert log =~ "rejected withdrawal"
      assert Decimal.equal?(Repo.reload!(account).balance, "10.00")
    end

    test "returns 404 for users without an account", %{conn: conn} do
      capture_log(fn ->
        conn = withdraw(conn, Ecto.UUID.generate(), %{amount: "1.00", target_currency: "EUR"})
        assert %{"error" => %{"code" => "account_not_found"}} = json_response(conn, 404)
      end)
    end

    @tag snapshot: :none
    test "returns 503 with retry-after while exchange rates are unavailable", %{
      conn: conn,
      account: account
    } do
      capture_log(fn ->
        conn = withdraw(conn, account.user_id, %{amount: "1.00", target_currency: "EUR"})

        assert %{"error" => %{"code" => "exchange_rates_unavailable"}} = json_response(conn, 503)
        assert get_resp_header(conn, "retry-after") == ["300"]
      end)
    end

    @tag snapshot: snapshot_fixture(fetched_at: ~U[2026-01-01 00:00:00Z])
    test "returns 503 when exchange rates are stale", %{conn: conn, account: account} do
      capture_log(fn ->
        conn = withdraw(conn, account.user_id, %{amount: "1.00", target_currency: "EUR"})
        assert %{"error" => %{"code" => "exchange_rates_unavailable"}} = json_response(conn, 503)
      end)
    end
  end

  describe "authentication" do
    test "requires a bearer token", %{conn: conn} do
      capture_log(fn ->
        conn = post(conn, ~p"/api/withdraw", %{})

        assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
        assert [~s(Bearer realm="api")] = get_resp_header(conn, "www-authenticate")
      end)
    end

    test "rejects other authorization schemes", %{conn: conn} do
      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Basic dXNlcjpwYXNz")
          |> post(~p"/api/withdraw", %{})

        assert json_response(conn, 401)
      end)
    end

    test "rejects invalid tokens", %{conn: conn} do
      capture_log(fn ->
        conn =
          conn
          |> put_req_header("authorization", "Bearer garbage")
          |> post(~p"/api/withdraw", %{})

        assert %{"error" => %{"message" => "Token is invalid or expired."}} =
                 json_response(conn, 401)
      end)
    end

    test "rejects revoked tokens", %{conn: conn, account: account} do
      jti = "jti-#{account.user_id}"
      expect(RevocationStoreMock, :revoked?, fn ^jti -> {:ok, true} end)

      capture_log(fn ->
        conn = withdraw(conn, account.user_id, %{amount: "1.00", target_currency: "EUR"})
        assert %{"error" => %{"message" => "Token has been revoked."}} = json_response(conn, 401)
      end)

      assert Decimal.equal?(OpenfnTest.Accounts.available_balance(account), "1000.00")
    end

    test "returns 503 while the identity provider is unavailable", %{conn: conn, account: account} do
      expect(TokenVerifierMock, :verify, fn _ -> {:error, :provider_not_ready} end)

      capture_log(fn ->
        conn = withdraw(conn, account.user_id, %{amount: "1.00", target_currency: "EUR"})
        assert %{"error" => %{"code" => "auth_unavailable"}} = json_response(conn, 503)
        assert get_resp_header(conn, "retry-after") == ["5"]
      end)
    end
  end
end
