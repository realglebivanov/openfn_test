defmodule OpenfnTestWeb.WithdrawalJSON do
  alias OpenfnTest.Accounts.Withdrawal

  def show(%{withdrawal: %Withdrawal{} = withdrawal}) do
    %{
      id: "wd_#{withdrawal.id}",
      account_id: "acc_#{withdrawal.account_id}",
      status: withdrawal.status,
      authorisation_code: authorisation_code(withdrawal),
      amount_usd: decimal(withdrawal.amount_usd),
      target_currency: withdrawal.target_currency,
      converted_amount: decimal(withdrawal.converted_amount),
      exchange_rate: decimal(withdrawal.exchange_rate),
      exchange_rate_fetched_at: datetime(withdrawal.exchange_rate_fetched_at),
      created_at: datetime(withdrawal.inserted_at)
    }
  end

  defp authorisation_code(%Withdrawal{status: "authorised"} = withdrawal),
    do: Withdrawal.authorisation_code(withdrawal)

  defp authorisation_code(%Withdrawal{}), do: nil

  defp decimal(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp datetime(%DateTime{} = value),
    do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
