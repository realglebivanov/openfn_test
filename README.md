# OpenfnTest: withdrawals API

A Phoenix service that authorises withdrawals from USD bank accounts and pays them out in a
currency the caller picks. Callers authenticate with Keycloak bearer tokens. Exchange rates
come from [Frankfurter](https://frankfurter.dev).

## Running it

```sh
docker compose up --build
```

This starts Postgres, Redis, Keycloak and the app. The app waits for Keycloak's readiness
check, then runs migrations and seeds, and listens on http://localhost:4000. If a host port is
already taken, override it with `POSTGRES_HOST_PORT`, `REDIS_HOST_PORT`, `KEYCLOAK_HOST_PORT`
or `APP_HOST_PORT`.

The Keycloak realm `openfn` is imported from [keycloak/openfn-realm.json](keycloak/openfn-realm.json):

| user  | password       | account | balance     |
|-------|----------------|---------|-------------|
| alice | alice-password | acc_1   | 1000.00 USD |
| bob   | bob-password   | acc_2   | 10.00 USD   |

```sh
TOKEN=$(curl -s http://localhost:8080/realms/openfn/protocol/openid-connect/token \
  -d grant_type=password -d client_id=openfn-api -d client_secret=openfn-api-secret \
  -d username=alice -d password=alice-password | jq -r .access_token)

curl -i http://localhost:4000/api/withdraw \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"amount": "125.50", "target_currency": "EUR"}'
```

```json
{
  "id": "wd_1",
  "account_id": "acc_1",
  "status": "authorised",
  "authorisation_code": "AAAA-AAAB",
  "amount_usd": "125.50",
  "target_currency": "EUR",
  "converted_amount": "111.80",
  "exchange_rate": "0.89087",
  "exchange_rate_fetched_at": "2026-10-19T17:08:23Z",
  "created_at": "2026-10-19T17:09:11Z"
}
```

## API

| route                   | auth   | description                                                        |
|-------------------------|--------|--------------------------------------------------------------------|
| `POST /api/withdraw`    | bearer | `{"amount": "125.50", "target_currency": "EUR"}` → 201 or 422      |
| `GET /api/healthcheck`  | none   | 200 while a fresh exchange rate dictionary is cached, 503 otherwise |
| `POST /api/revoke`      | none   | `{"token": "<access token>"}` revokes that token until it expires  |

The account is the one owned by the token's subject (`sub`). Withdrawals don't change the
account balance: every request is stored as a withdrawal, `authorised` (201) when the balance
minus the already authorised withdrawals covers it, `rejected` (422) otherwise. Both responses
have the withdrawal body above; a rejected one has `"authorisation_code": null`.

Errors use one shape, `{"error": {"code": "...", "message": "..."}}`:

| status | code                         | when                                                        |
|--------|------------------------------|-------------------------------------------------------------|
| 400    | `parse_error`                | body is not valid JSON or not a JSON object                 |
| 401    | `unauthorized`               | token is missing, malformed, invalid, expired or revoked    |
| 404    | `account_not_found`          | the authenticated user has no account                       |
| 422    | `validation_error`           | body doesn't match the schema (`details` lists the problems) |
| 422    | `invalid_currency`           | the currency is well formed but has no exchange rate        |
| 503    | `exchange_rates_unavailable` | no fresh rates are cached (`Retry-After` is set)            |
| 503    | `auth_unavailable`           | Keycloak config or Redis is unreachable (`Retry-After` is set) |

## Development

```sh
docker compose up -d postgres redis keycloak
mix setup
mix phx.server
```

Tokens are issued for `http://keycloak:8080`, so when running the app on the host add
`127.0.0.1 keycloak` to `/etc/hosts`. The Keycloak admin console is at http://localhost:8080
(admin/admin).

Tests need Postgres on `localhost:5432` (user and password `postgres`). Keycloak, Redis and
Frankfurter are replaced by Mox mocks and `Req.Test` stubs, so the tests don't need them.

```sh
mix test
mix precommit
```
