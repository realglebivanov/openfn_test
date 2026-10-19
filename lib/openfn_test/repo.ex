defmodule OpenfnTest.Repo do
  use Ecto.Repo,
    otp_app: :openfn_test,
    adapter: Ecto.Adapters.Postgres
end
