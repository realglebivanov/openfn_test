## Design

The sections following the Design section are the generic design requirements
Here's how to approach the design specifically:

### Infrastructure
- Docker compose with a postgres, keyloak and the app
- Postgres should use read commited transation isolation level
- Docker compose should await the keycloak initialization on start
- Keycloak should contain a sample user/password.

### App architecture & implementation
#### DB & transactions
- Two entities. Account and its withdrawals being kept in the corresponding postgres tables
- Accounts should just hold a user_id(unique), account_id(primary key), the balance, timestamps
- Withdrawals should hold id(primary key), account_id(foreign key), status, target currency, withdrawn amount, exchange rate fetched timestamp, timestamps. Derive authorization code from id using base64 encoding. Pad the code to at least 9 bytes(assuming ascii symbols only).
- Keep all the floating point values and operations as Decimal in elixir code and as decimal in the postgres
- Withdraw in a transaction, use select .. lock for update for accounts to prevent read/write skews

#### Authentication
- Implement an Auth plug that would verify the token using :oidcc package and the local keycloak instance.
- Protect /api/withdraw route only 
- Keep revoked keys in redis with a ttl and check this set before proceeding further

#### Exchange rates
- Implement /api/healthcheck route that would fail unless there's a cached exhange rate dictionary
- A background process that fetches exchange rates in the background, keeps them in `:ets`, cleans up the old ones.
- Keep all the floating point values as Decimal
- If the last cached entry is fetched before a certain timestamp, return an error
- Fetch the exchange rates using its client, keep the retry/backoff logic, response parsing and error handling in it. Log the failed fetch exchange rate attempts  

#### Request flow
- Logger.warning for all the errors
- Parse the request into a struct using ex_json_schema, enforce keys, be strict => next | parse error | validation error
- Fetch the latest exchange rate for a currency => next | 4xx invalid_currency | 5xx failed + retry header if unhealthy
- Try to withdraw in a transaction like described above => ok 

## The scenario
You’re building a web service that simulates bank accounts and exposes an endpoint to
authorize withdrawals. The account holder’s balance is held in USD, but the withdrawal is paid
out in a currency of the caller’s choosing.
What your server must do
- Authenticate the incoming HTTP request based on an incoming Authentication header
- Convert the withdrawal amount from USD into the requested target currency using an
external service.
- Check that the debit account has enough funds.
- Generate an authorisation code for the transaction.
- Return the authorisation code, or an error.

## API spec

POST /v1/accounts/{account_id}/withdrawals
Authorization: Bearer <token>
Content-Type: application/json

Request body:

JSON

JSON
{ "amount": "125.50", "target_currency": "EUR" }

- amount is in USD, sent as a decimal string.
- target_currency is an ISO 4217 code.

Success returns 201 Created:
```
{
    "id": "wd_8f3k2",
    "account_id": "acc_123",
    "status": "authorised",
    "authorisation_code": "A7Q2-91XK",
    "amount_usd": "125.50",
    "target_currency": "EUR",
    "converted_amount": "115.46",
    "exchange_rate": "0.92",
    "created_at": "2026-10-13T14:03:00Z"
}
```

## Currency exchange

We recommend you use Frankfurter, which is free and needs no API key.
What we leave to you
- Account storage: an in-memory mock, SQLite or a full database. Your choice, but be
ready to explain why.
- How accounts and tokens are created and validated.
- The format and generation of authorisation codes.
- Error handling
- Anything else the brief doesn’t specify.