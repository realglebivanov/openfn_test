defmodule OpenfnTest.Accounts.Withdrawal do
  @moduledoc """
  A withdrawal requested from an account.

  `status` is `"authorised"` when the account had enough available funds and `"rejected"`
  otherwise. Authorised `amount_usd`s count against the account balance, `converted_amount` is
  what gets paid out in `target_currency` using `exchange_rate` (fetched at
  `exchange_rate_fetched_at`).
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]

  @statuses ~w(authorised rejected)

  schema "withdrawals" do
    field :status, :string, default: "authorised"
    field :target_currency, :string
    field :amount_usd, :decimal
    field :exchange_rate, :decimal
    field :converted_amount, :decimal
    field :exchange_rate_fetched_at, :utc_datetime_usec

    belongs_to :account, OpenfnTest.Accounts.Account

    timestamps()
  end

  def statuses, do: @statuses

  # The code is at least 6 raw bytes, i.e. at least 8 base64 characters, grouped by 4 with
  # dashes: "AAAA-AAAB" is 9 bytes long.
  @min_raw_bytes 6
  @group_size 4

  @doc """
  Derives the authorisation code from the withdrawal id.

  The id is encoded as a big-endian unsigned integer, left-padded with zero bytes to a multiple
  of 3 bytes (and at least #{@min_raw_bytes} bytes) so base64 needs no `=` padding, then split into
  groups of #{@group_size} characters.

      iex> OpenfnTest.Accounts.Withdrawal.authorisation_code(%OpenfnTest.Accounts.Withdrawal{id: 1})
      "AAAA-AAAB"
  """
  def authorisation_code(%__MODULE__{id: id}) when is_integer(id) and id > 0 do
    raw = :binary.encode_unsigned(id)
    size = max(@min_raw_bytes, div(byte_size(raw) + 2, 3) * 3)
    padding = (size - byte_size(raw)) * 8

    <<0::size(padding), raw::binary>>
    |> Base.encode64()
    |> chunk()
    |> Enum.join("-")
  end

  defp chunk(<<group::binary-size(@group_size), rest::binary>>) when rest != "",
    do: [group | chunk(rest)]

  defp chunk(rest), do: [rest]
end
