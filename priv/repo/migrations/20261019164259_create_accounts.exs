defmodule OpenfnTest.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :user_id, :string, null: false
      add :balance, :decimal, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:accounts, [:user_id])

    create constraint(:accounts, :balance_must_be_non_negative, check: "balance >= 0")
  end
end
