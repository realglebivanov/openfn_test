defmodule OpenfnTestWeb.WithdrawalController do
  use OpenfnTestWeb, :controller

  require Logger

  alias OpenfnTest.{Accounts, ExchangeRates}
  alias OpenfnTest.Accounts.{Withdrawal, WithdrawalRequest}

  action_fallback OpenfnTestWeb.FallbackController

  def create(conn, _params) do
    with {:ok, request} <- WithdrawalRequest.parse(conn.body_params),
         {:ok, rate} <- ExchangeRates.get_rate(request.target_currency),
         {:ok, withdrawal} <- Accounts.withdraw(conn.assigns.current_user.user_id, request, rate) do
      conn
      |> put_status(status(conn, withdrawal))
      |> render(:show, withdrawal: withdrawal)
    end
  end

  defp status(_conn, %Withdrawal{status: "authorised"}), do: :created

  defp status(conn, %Withdrawal{status: "rejected"} = withdrawal) do
    Logger.warning(
      "#{conn.method} #{conn.request_path} rejected withdrawal wd_#{withdrawal.id}: insufficient funds"
    )

    :unprocessable_entity
  end
end
