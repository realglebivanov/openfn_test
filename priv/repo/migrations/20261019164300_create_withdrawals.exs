defmodule OpenfnTest.Repo.Migrations.CreateWithdrawals do
  use Ecto.Migration

  def change do
    create table(:withdrawals) do
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :status, :string, null: false
      add :target_currency, :string, size: 3, null: false
      add :amount_usd, :decimal, null: false
      add :exchange_rate, :decimal, null: false
      add :converted_amount, :decimal, null: false
      add :exchange_rate_fetched_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:withdrawals, [:account_id])

    create constraint(:withdrawals, :amount_usd_must_be_positive, check: "amount_usd > 0")
  end
end
