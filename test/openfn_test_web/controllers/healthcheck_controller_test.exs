defmodule OpenfnTestWeb.HealthcheckControllerTest do
  # Not async: uses the globally named exchange rates cache.
  use OpenfnTestWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import OpenfnTest.Fixtures

  alias OpenfnTest.ExchangeRates.Fetcher

  defp start_fetcher(result) do
    pid = start_supervised!({Fetcher, fetch: fn -> result end})
    _ = :sys.get_state(pid)
  end

  test "is healthy with fresh exchange rates", %{conn: conn} do
    start_fetcher({:ok, snapshot_fixture()})

    assert %{"status" => "ok", "exchange_rates" => %{"base" => "USD", "currencies" => 4}} =
             conn |> get(~p"/api/healthcheck") |> json_response(200)
  end

  test "is unhealthy without exchange rates", %{conn: conn} do
    capture_log(fn ->
      start_fetcher({:error, :boom})
      conn = get(conn, ~p"/api/healthcheck")

      assert %{"error" => %{"code" => "exchange_rates_unavailable"}} = json_response(conn, 503)
      assert get_resp_header(conn, "retry-after") == ["300"]
    end)
  end

  test "is unhealthy with stale exchange rates", %{conn: conn} do
    start_fetcher({:ok, snapshot_fixture(fetched_at: ~U[2026-01-01 00:00:00Z])})

    capture_log(fn ->
      assert conn |> get(~p"/api/healthcheck") |> json_response(503)
    end)
  end

  test "is unhealthy when the fetcher is not running", %{conn: conn} do
    capture_log(fn ->
      assert conn |> get(~p"/api/healthcheck") |> json_response(503)
    end)
  end
end
