defmodule OpenfnTestWeb.Router do
  use OpenfnTestWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug OpenfnTestWeb.Plugs.Auth
  end

  scope "/api", OpenfnTestWeb do
    pipe_through :api

    get "/healthcheck", HealthcheckController, :show
    post "/revoke", TokenRevocationController, :create
  end

  scope "/api", OpenfnTestWeb do
    pipe_through [:api, :authenticated]

    post "/withdraw", WithdrawalController, :create
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:openfn_test, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
