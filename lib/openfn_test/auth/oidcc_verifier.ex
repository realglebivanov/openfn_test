defmodule OpenfnTest.Auth.OidccVerifier do
  @moduledoc """
  Verifies JWT access tokens issued by the configured OpenID provider (Keycloak).

  The provider configuration and its signing keys (JWKS) are fetched and kept fresh by an
  `Oidcc.ProviderConfiguration.Worker` started under the application supervisor, so verifying
  a token doesn't need a round trip to the provider. Signature, `iss`, `aud` (must contain our
  client id), `exp` and `nbf` are checked.
  """
  @behaviour OpenfnTest.Auth.TokenVerifier

  @provider OpenfnTest.Auth.OidcProvider

  def child_spec(_opts) do
    config = config()

    Oidcc.ProviderConfiguration.Worker.child_spec(%{
      name: @provider,
      issuer: Keyword.fetch!(config, :issuer),
      provider_configuration_opts: %{
        quirks: %{allow_unsafe_http: Keyword.get(config, :allow_unsafe_http, false)}
      },
      backoff_type: :random_exponential,
      backoff_min: 1_000,
      backoff_max: 30_000
    })
  end

  @impl true
  def verify(token) do
    config = config()

    with {:ok, client_context} <-
           Oidcc.ClientContext.from_configuration_worker(
             @provider,
             Keyword.fetch!(config, :client_id),
             Keyword.fetch!(config, :client_secret)
           ) do
      Oidcc.Token.validate_jwt(token, client_context, %{
        signing_algs: Keyword.fetch!(config, :signing_algs)
      })
    end
  end

  defp config, do: Application.fetch_env!(:openfn_test, OpenfnTest.Auth)
end
