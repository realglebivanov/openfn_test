defmodule OpenfnTest.AccountsTest do
  use OpenfnTest.DataCase, async: true

  import OpenfnTest.Fixtures

  alias OpenfnTest.Accounts
  alias OpenfnTest.Accounts.{Account, Withdrawal, WithdrawalRequest}
  alias OpenfnTest.ExchangeRates.Rate

  defp request(amount, currency \\ "EUR"),
    do: %WithdrawalRequest{amount_usd: Decimal.new(amount), target_currency: currency}

  defp rate(rate, currency \\ "EUR"),
    do: %Rate{
      currency: currency,
      rate: Decimal.new(rate),
      fetched_at: ~U[2026-10-19 10:00:00.000000Z]
    }

  describe "withdraw/3" do
    test "records an authorised withdrawal and leaves the balance untouched" do
      account = account_fixture(balance: "1000.00")

      assert {:ok, %Withdrawal{} = withdrawal} =
               Accounts.withdraw(account.user_id, request("125.50"), rate("0.92"))

      assert withdrawal.account_id == account.id
      assert withdrawal.status == "authorised"
      assert withdrawal.target_currency == "EUR"
      assert Decimal.equal?(withdrawal.amount_usd, "125.50")
      assert Decimal.equal?(withdrawal.exchange_rate, "0.92")
      assert Decimal.equal?(withdrawal.converted_amount, "115.46")
      assert withdrawal.exchange_rate_fetched_at == ~U[2026-10-19 10:00:00.000000Z]

      assert Decimal.equal?(Repo.reload!(account).balance, "1000.00")
      assert Decimal.equal?(Accounts.available_balance(account), "874.50")
      assert Repo.get!(Withdrawal, withdrawal.id).converted_amount == Decimal.new("115.46")
    end

    test "rounds the converted amount to cents" do
      account = account_fixture()

      # 10.01 * 0.7891 = 7.898891
      assert {:ok, withdrawal} =
               Accounts.withdraw(account.user_id, request("10.01", "GBP"), rate("0.7891", "GBP"))

      assert Decimal.to_string(withdrawal.converted_amount) == "7.90"
    end

    test "converts large amounts exactly" do
      amount = String.duplicate("9", 32) <> ".99"
      account = account_fixture(balance: amount)

      assert {:ok, withdrawal} =
               Accounts.withdraw(account.user_id, request(amount, "JPY"), rate("151.23", "JPY"))

      assert withdrawal.status == "authorised"

      assert Decimal.to_string(withdrawal.converted_amount) ==
               "15122999999999999999999999999999998.49"

      assert Decimal.to_string(Repo.get!(Withdrawal, withdrawal.id).converted_amount) ==
               "15122999999999999999999999999999998.49"
    end

    test "computes the available balance beyond Decimal's precision" do
      balance = Decimal.new("2" <> String.duplicate("0", 33) <> ".00", max_digits: :infinity)
      account = account_fixture(balance: balance)
      amount = String.duplicate("9", 32) <> ".99"

      for _ <- 1..2 do
        assert {:ok, %Withdrawal{status: "authorised"}} =
                 Accounts.withdraw(account.user_id, request(amount), rate("0.92"))
      end

      assert Decimal.to_string(Accounts.available_balance(account)) ==
               "1800000000000000000000000000000000.02"
    end

    test "allows withdrawing the whole balance" do
      account = account_fixture(balance: "50.00")

      assert {:ok, _} = Accounts.withdraw(account.user_id, request("50.00"), rate("0.92"))
      assert Decimal.equal?(Accounts.available_balance(account), 0)
    end

    test "keeps a rejected withdrawal when funds are insufficient" do
      account = account_fixture(balance: "10.00")

      assert {:ok, %Withdrawal{} = withdrawal} =
               Accounts.withdraw(account.user_id, request("10.01"), rate("0.92"))

      assert [%Withdrawal{id: id}] = Repo.all(Withdrawal)
      assert id == withdrawal.id
      assert withdrawal.account_id == account.id
      assert withdrawal.status == "rejected"
      assert Decimal.equal?(withdrawal.amount_usd, "10.01")
      assert Decimal.equal?(withdrawal.converted_amount, "9.21")

      assert Decimal.equal?(Repo.reload!(account).balance, "10.00")
      assert Decimal.equal?(Accounts.available_balance(account), "10.00")
    end

    test "counts only authorised withdrawals against the balance" do
      account = account_fixture(balance: "100.00")

      assert {:ok, %Withdrawal{status: "authorised"}} =
               Accounts.withdraw(account.user_id, request("60.00"), rate("0.92"))

      assert {:ok, %Withdrawal{status: "rejected"}} =
               Accounts.withdraw(account.user_id, request("50.00"), rate("0.92"))

      assert {:ok, %Withdrawal{status: "authorised"}} =
               Accounts.withdraw(account.user_id, request("40.00"), rate("0.92"))

      assert Decimal.equal?(Accounts.available_balance(account), 0)

      assert Withdrawal |> select([w], w.status) |> order_by(:id) |> Repo.all() ==
               ~w(authorised rejected authorised)
    end

    test "fails when the user has no account" do
      assert {:error, :account_not_found} =
               Accounts.withdraw(Ecto.UUID.generate(), request("1.00"), rate("0.92"))
    end
  end

  describe "ensure_account/2" do
    test "creates the account once" do
      user_id = Ecto.UUID.generate()

      assert {:ok, %Account{} = account} = Accounts.ensure_account(user_id, Decimal.new("5.00"))
      assert {:ok, ^account} = Accounts.ensure_account(user_id, Decimal.new("100.00"))
      assert Decimal.equal?(account.balance, "5.00")
    end
  end
end
