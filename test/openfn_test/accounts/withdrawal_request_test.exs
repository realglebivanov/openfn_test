defmodule OpenfnTest.Accounts.WithdrawalRequestTest do
  use ExUnit.Case, async: true

  alias OpenfnTest.Accounts.WithdrawalRequest

  test "parses a valid request" do
    assert {:ok, %WithdrawalRequest{amount_usd: amount, target_currency: "EUR"}} =
             WithdrawalRequest.parse(%{"amount" => "125.5", "target_currency" => "EUR"})

    assert Decimal.to_string(amount) == "125.50"
  end

  test "accepts whole amounts" do
    assert {:ok, %WithdrawalRequest{amount_usd: amount}} =
             WithdrawalRequest.parse(%{"amount" => "10", "target_currency" => "EUR"})

    assert Decimal.equal?(amount, 10)
  end

  test "accepts amounts with up to 32 integer digits" do
    amount = String.duplicate("9", 32) <> ".99"

    assert {:ok, %WithdrawalRequest{amount_usd: parsed}} =
             WithdrawalRequest.parse(%{"amount" => amount, "target_currency" => "EUR"})

    assert Decimal.to_string(parsed) == amount
  end

  test "rejects amounts Decimal can't hold" do
    for amount <- [
          String.duplicate("9", 33),
          String.duplicate("1", 33) <> ".5",
          "1" <> String.duplicate("0", 500)
        ] do
      assert {:error,
              {:validation_error,
               [%{path: "#/amount", message: "Must have at most 32 integer digits."}]}} =
               WithdrawalRequest.parse(%{"amount" => amount, "target_currency" => "EUR"})
    end
  end

  test "rejects non-object bodies" do
    assert {:error, :parse_error} = WithdrawalRequest.parse(%{"_json" => [1, 2]})
    assert {:error, :parse_error} = WithdrawalRequest.parse("125.50")
  end

  test "requires all keys" do
    assert {:error, {:validation_error, [%{path: "#", message: message}]}} =
             WithdrawalRequest.parse(%{"amount" => "1.00"})

    assert message =~ "target_currency"
  end

  test "rejects unknown keys" do
    assert {:error, {:validation_error, [%{path: "#/account_id"}]}} =
             WithdrawalRequest.parse(%{
               "amount" => "1.00",
               "target_currency" => "EUR",
               "account_id" => "acc_1"
             })
  end

  for amount <- [125.5, "-1.00", "1.234", "1e3", "01.00", "abc", "", " 1.00", "1."] do
    test "rejects amount #{inspect(amount)}" do
      assert {:error, {:validation_error, [%{path: "#/amount"} | _]}} =
               WithdrawalRequest.parse(%{
                 "amount" => unquote(amount),
                 "target_currency" => "EUR"
               })
    end
  end

  test "rejects a zero amount" do
    for amount <- ["0", "0.00"] do
      assert {:error,
              {:validation_error, [%{path: "#/amount", message: "Must be greater than 0."}]}} =
               WithdrawalRequest.parse(%{"amount" => amount, "target_currency" => "EUR"})
    end
  end

  for currency <- ["eur", "EURO", "EU", 978, nil] do
    test "rejects target_currency #{inspect(currency)}" do
      assert {:error, {:validation_error, [%{path: "#/target_currency"} | _]}} =
               WithdrawalRequest.parse(%{
                 "amount" => "1.00",
                 "target_currency" => unquote(currency)
               })
    end
  end
end
