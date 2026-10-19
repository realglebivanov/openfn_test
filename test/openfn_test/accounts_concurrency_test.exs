defmodule OpenfnTest.AccountsConcurrencyTest do
  # Runs real concurrent transactions, outside of the SQL sandbox, so the row lock is exercised.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias OpenfnTest.{Accounts, Repo}
  alias OpenfnTest.Accounts.{Account, Withdrawal, WithdrawalRequest}
  alias OpenfnTest.ExchangeRates.Rate

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    account =
      Repo.insert!(%Account{user_id: Ecto.UUID.generate(), balance: Decimal.new("100.00")})

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from w in Withdrawal, where: w.account_id == ^account.id)
      Repo.delete!(account)
    end)

    %{account: account}
  end

  test "concurrent withdrawals never overdraw the account", %{account: account} do
    request = %WithdrawalRequest{amount_usd: Decimal.new("30.00"), target_currency: "EUR"}
    rate = %Rate{currency: "EUR", rate: Decimal.new("0.92"), fetched_at: DateTime.utc_now()}

    results =
      1..10
      |> Task.async_stream(
        fn _ ->
          :ok = Sandbox.checkout(Repo, sandbox: false)
          Accounts.withdraw(account.user_id, request, rate)
        end,
        max_concurrency: 10,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert results
           |> Enum.map(fn {:ok, %Withdrawal{status: status}} -> status end)
           |> Enum.frequencies() == %{"authorised" => 3, "rejected" => 7}

    assert Decimal.equal?(Repo.reload!(account).balance, "100.00")
    assert Decimal.equal?(Accounts.available_balance(account), "10.00")

    statuses =
      Repo.all(from w in Withdrawal, where: w.account_id == ^account.id, select: w.status)

    assert Enum.frequencies(statuses) == %{"authorised" => 3, "rejected" => 7}
  end
end
