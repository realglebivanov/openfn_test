defmodule OpenfnTest.Accounts.Account do
  @moduledoc """
  A bank account owned by an identity provider user (`user_id` is the token `sub`).

  The balance is held in USD and isn't changed by withdrawals: authorised withdrawals are
  subtracted from it to get the available balance (see `OpenfnTest.Accounts.available_balance/1`).
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]

  schema "accounts" do
    field :user_id, :string
    field :balance, :decimal

    has_many :withdrawals, OpenfnTest.Accounts.Withdrawal

    timestamps()
  end
end
