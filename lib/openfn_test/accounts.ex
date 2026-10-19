defmodule OpenfnTest.Accounts do
  @moduledoc """
  Accounts and withdrawals.
  """

  import Ecto.Query, warn: false

  alias OpenfnTest.Repo
  alias OpenfnTest.Accounts.{Account, Withdrawal, WithdrawalRequest}
  alias OpenfnTest.ExchangeRates.Rate

  @doc """
  Returns the account of the given user, if any.
  """
  def get_account_by_user_id(user_id), do: Repo.get_by(Account, user_id: user_id)

  @doc """
  Creates an account for `user_id` with the given USD balance unless it already exists.
  """
  def ensure_account(user_id, %Decimal{} = balance) do
    Repo.insert(%Account{user_id: user_id, balance: balance},
      on_conflict: :nothing,
      conflict_target: :user_id
    )

    {:ok, get_account_by_user_id(user_id)}
  end

  @doc """
  Returns the USD amount still available for withdrawal: the account balance minus the sum of
  its authorised withdrawals.

  Computed by Postgres, whose `numeric` arithmetic is exact at any size, unlike `Decimal`'s,
  which rounds results to the context precision.
  """
  @spec available_balance(Account.t()) :: Decimal.t()
  def available_balance(%Account{id: account_id}) do
    Repo.one(
      from a in Account,
        left_join: w in Withdrawal,
        on: w.account_id == a.id and w.status == "authorised",
        where: a.id == ^account_id,
        group_by: a.id,
        select: type(a.balance - coalesce(sum(w.amount_usd), 0), :decimal)
    )
  end

  @doc """
  Requests a withdrawal of `request.amount_usd` from the user's account paid out in
  `request.target_currency` at the given `rate`.

  The account balance itself is never changed. The withdrawal is recorded as `"authorised"` when
  the available balance (see `available_balance/1`) covers it, and as `"rejected"` otherwise.
  Both outcomes are stored and returned as `{:ok, withdrawal}`.

  Runs in a single transaction. The account row is locked with `SELECT ... FOR UPDATE` before
  the available balance is computed, so concurrent withdrawals from the same account are
  serialised and can't overdraw it (no read/write skew under READ COMMITTED).
  """
  @spec withdraw(String.t(), WithdrawalRequest.t(), Rate.t()) ::
          {:ok, Withdrawal.t()} | {:error, :account_not_found}
  def withdraw(
        user_id,
        %WithdrawalRequest{amount_usd: amount, target_currency: currency},
        %Rate{currency: currency} = rate
      ) do
    Repo.transact(fn ->
      with {:ok, account} <- lock_account(user_id) do
        Repo.insert(%Withdrawal{
          account_id: account.id,
          status: status(available_balance(account), amount),
          target_currency: currency,
          amount_usd: amount,
          exchange_rate: rate.rate,
          converted_amount: convert(amount, rate.rate),
          exchange_rate_fetched_at: rate.fetched_at
        })
      end
    end)
  end

  defp lock_account(user_id) do
    Account
    |> where(user_id: ^user_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :account_not_found}
      account -> {:ok, account}
    end
  end

  # `amount * rate` rounded to cents. The precision is raised to fit the exact product, plus a
  # digit for a rounding carry, so large amounts are neither rounded early nor rejected by
  # `Decimal.round/3`.
  defp convert(amount, rate) do
    context = Decimal.Context.get()
    precision = max(context.precision, digits(amount) + digits(rate) + 1)

    Decimal.Context.with(%{context | precision: precision}, fn ->
      amount |> Decimal.mult(rate) |> Decimal.round(2, :half_up)
    end)
  end

  # Digits of the integer coefficient, plus the trailing zeros `Decimal.round/3` pads a positive
  # exponent out to.
  defp digits(%Decimal{coef: coef, exp: exp}), do: length(Integer.digits(coef)) + max(exp, 0)

  defp status(available, amount) do
    if Decimal.compare(amount, available) == :gt, do: "rejected", else: "authorised"
  end
end
