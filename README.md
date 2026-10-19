## Assumptions

- One USD account per Keycloak user, linked by `sub`, so the route is `POST /api/withdraw`
  with no account id in the path. Accounts come from the seeds; there's no sign-up endpoint.
- Authorising a withdrawal is a hold, not a debit: available = balance − authorised
  withdrawals. Rejected attempts are stored too. There are no idempotency keys.
- `amount` is positive with at most 2 decimal places. `converted_amount` is rounded half-up
  to 2 places for every currency. Money is always `Decimal` / `numeric`, never a float.
- A currency is valid if Frankfurter has a rate for it. Rates are refreshed every 5 minutes
  and used for up to 1 hour; after that withdrawals return 503.
- The authorisation code is the withdrawal id in base64. It's a unique reference, not a
  secret.
- Postgres at READ COMMITTED, with `SELECT ... FOR UPDATE` on the account row, so concurrent
  withdrawals can't overdraw.

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

## AI usage

- I wrote [DESIGN.md](DESIGN.md) first: the brief plus my architecture decisions.
  Claude Code implemented it, following the Phoenix guidelines in [AGENTS.md](AGENTS.md).
- I reviewed and corrected every change.
- This README was drafted with AI and edited by me.
