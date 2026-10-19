defmodule OpenfnTest.ExchangeRates.ClientTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias OpenfnTest.ExchangeRates.{Client, Snapshot}

  setup {Req.Test, :verify_on_exit!}

  @body ~s([
    {"date":"2026-10-16","base":"USD","quote":"EUR","rate":0.92048},
    {"date":"2026-10-15","base":"USD","quote":"GBP","rate":0.7891},
    {"date":"2026-10-16","base":"USD","quote":"IDR","rate":16250},
    {"date":"2026-10-16","base":"USD","quote":"USD","rate":1.0}
  ])

  defp ok(conn),
    do:
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, @body)

  test "fetches the latest USD rates as decimals" do
    Req.Test.expect(Client, fn conn ->
      assert conn.request_path == "/v2/rates"
      assert conn.query_params == %{"base" => "USD"}
      ok(conn)
    end)

    assert {:ok,
            %Snapshot{base: "USD", date: ~D[2026-10-16], rates: rates, fetched_at: %DateTime{}}} =
             Client.fetch_latest()

    assert rates == %{
             "EUR" => Decimal.new("0.92048"),
             "GBP" => Decimal.new("0.7891"),
             "IDR" => Decimal.new(16250),
             "USD" => Decimal.new(1)
           }
  end

  test "retries transient failures and logs every failed attempt" do
    Req.Test.expect(Client, &Plug.Conn.send_resp(&1, 503, "unavailable"))
    Req.Test.expect(Client, &Req.Test.transport_error(&1, :econnrefused))
    Req.Test.expect(Client, &ok/1)

    log =
      capture_log(fn ->
        assert {:ok, %Snapshot{}} = Client.fetch_latest()
      end)

    assert log =~ "attempt 1/3 failed: {:http_status, 503}"
    assert log =~ "attempt 2/3 failed: {:transport_error"
  end

  test "gives up after max attempts" do
    Req.Test.expect(Client, 3, &Plug.Conn.send_resp(&1, 500, "boom"))

    log =
      capture_log(fn ->
        assert {:error, {:http_status, 500}} = Client.fetch_latest()
      end)

    assert log =~ "attempt 3/3 failed"
  end

  test "does not retry client errors" do
    Req.Test.expect(Client, &Plug.Conn.send_resp(&1, 404, "not found"))

    capture_log(fn ->
      assert {:error, {:http_status, 404}} = Client.fetch_latest()
    end)
  end

  test "does not retry malformed responses" do
    for body <- [
          "not json",
          "[]",
          ~s([1,2,3]),
          ~s({"base":"USD","date":"2026-10-16","rates":{"EUR":0.92}}),
          ~s([{"date":"2026-10-16","base":"EUR","quote":"GBP","rate":0.86}]),
          ~s([{"date":"yesterday","base":"USD","quote":"EUR","rate":0.92}]),
          ~s([{"base":"USD","quote":"EUR","rate":0.92}]),
          ~s([{"date":"2026-10-16","base":"USD","quote":"EUR","rate":"0.92"}]),
          ~s([{"date":"2026-10-16","base":"USD","quote":"EUR","rate":-1}]),
          ~s([{"date":"2026-10-16","base":"USD","quote":"EUR","rate":0}])
        ] do
      Req.Test.expect(Client, &Plug.Conn.send_resp(&1, 200, body))

      assert {:error, {:invalid_response, _}} = Client.fetch_latest()
    end
  end
end
