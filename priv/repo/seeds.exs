# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# or, in a release, with `bin/seed`.
#
# Creates accounts for the sample Keycloak users (see keycloak/openfn-realm.json), whose ids
# are fixed so the token `sub` claim matches `accounts.user_id`. Safe to run more than once.

alias OpenfnTest.Accounts

for {username, user_id, balance} <- [
      {"alice", "3f6c2a54-8d1e-4b7a-9c2f-5e1d7a8b9c01", "1000.00"},
      {"bob", "8a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", "10.00"}
    ] do
  {:ok, account} = Accounts.ensure_account(user_id, Decimal.new(balance))
  IO.puts("Account acc_#{account.id} for #{username}: #{account.balance} USD")
end
