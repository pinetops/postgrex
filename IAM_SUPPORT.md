# Postgrex IAM Authentication Support

This branch adds native support for IAM-based authentication to Postgrex, enabling secure connections to cloud databases like Google Cloud AlloyDB, AWS RDS, and Azure Database for PostgreSQL without hardcoded passwords.

## Features Added

### 1. Password Provider Option

A new `:password_provider` option that accepts a callback function or MFA tuple to supply passwords at connection time:

```elixir
# Using a function
Postgrex.start_link(
  hostname: "db.example.com",
  username: "user@example.com",
  password_provider: fn -> get_oauth_token() end
)

# Using MFA tuple
Postgrex.start_link(
  hostname: "db.example.com",
  username: "user@example.com",
  password_provider: {MyAuth, :get_token, []}
)
```

The provider is called on each (re)connect, ensuring fresh tokens for long-lived connections.

### 2. TLS Profile Support

New `:ssl_profile` option with predefined secure configurations:

```elixir
# Strict profile with certificate verification
Postgrex.start_link(
  hostname: "db.example.com",
  ssl: true,
  ssl_profile: :strict  # Enables verify_peer, SNI, system CAs
)

# Cloud profile optimized for cloud providers
Postgrex.start_link(
  hostname: "project.region.alloydb.goog",
  ssl: true,
  ssl_profile: :cloud  # Like :strict but with depth: 3
)
```

### 3. TLS Helper Module

New `Postgrex.TLS` module with helper functions:

```elixir
# Get strict TLS options
ssl_opts = Postgrex.TLS.strict_opts!("db.example.com")

# Get cloud-optimized TLS options
ssl_opts = Postgrex.TLS.cloud_opts!("cloud.db.com")

# With custom overrides
ssl_opts = Postgrex.TLS.strict_opts!("db.example.com", depth: 5)
```

## Use Cases

### Google Cloud AlloyDB with IAM

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres
end

# config/runtime.exs
config :my_app, MyApp.Repo,
  hostname: System.fetch_env!("ALLOYDB_HOST"),
  database: System.fetch_env!("ALLOYDB_DATABASE"),
  username: System.fetch_env!("IAM_DB_USER"),  # e.g., "user@example.com"
  password_provider: {MyApp.Auth, :get_gcp_token, []},
  ssl: true,
  ssl_profile: :cloud,
  pool_size: 10

defmodule MyApp.Auth do
  def get_gcp_token do
    # Use Google Cloud SDK or service account to get OAuth2 token
    {token, 0} = System.cmd("gcloud", ["auth", "print-access-token"])
    String.trim(token)
  end
end
```

### AWS RDS with IAM Authentication

```elixir
config :my_app, MyApp.Repo,
  hostname: "mydb.123456789012.us-east-1.rds.amazonaws.com",
  database: "postgres",
  username: "iam_db_user",
  password_provider: {MyApp.Auth, :get_rds_token, []},
  ssl: true,
  ssl_profile: :strict

defmodule MyApp.Auth do
  def get_rds_token do
    # Generate RDS IAM auth token using AWS SDK
    ExAws.RDS.generate_db_auth_token(
      hostname: "mydb.123456789012.us-east-1.rds.amazonaws.com",
      port: 5432,
      username: "iam_db_user"
    )
  end
end
```

### HashiCorp Vault Integration

```elixir
config :my_app, MyApp.Repo,
  hostname: "localhost",
  database: "myapp",
  username: "vault_user",
  password_provider: {MyApp.Vault, :get_password, []},
  ssl: false

defmodule MyApp.Vault do
  def get_password do
    {:ok, %{"data" => %{"password" => password}}} = 
      Vault.read("database/creds/myapp")
    password
  end
end
```

## Implementation Details

### Modified Files

1. **lib/postgrex.ex**
   - Added `password_provider` type and option documentation
   - Added `ssl_profile` option documentation

2. **lib/postgrex/protocol.ex**
   - Added `get_password/1` helper function
   - Modified `auth_cleartext/3` and `auth_md5/4` to use password provider
   - Added TLS profile support in connection setup

3. **lib/postgrex/scram.ex**
   - Added `get_password/1` helper function
   - Modified SCRAM authentication to use password provider

4. **lib/postgrex/tls.ex** (new file)
   - TLS configuration helper module
   - `strict_opts!/2` and `cloud_opts!/2` functions
   - `apply_profile/3` for profile application logic

### Backward Compatibility

All changes are fully backward compatible:
- If no `password_provider` is specified, the regular `:password` option is used
- If no `ssl_profile` is specified, existing SSL behavior is unchanged
- Explicit `ssl_opts` always take precedence over profiles

## Testing

Run the included test suite:

```bash
# Simple functional test
mix run simple_test.exs

# Unit tests (requires test environment setup)
mix test test/password_provider_test.exs
```

## Benefits

1. **Security**: No hardcoded passwords in configuration or environment variables
2. **Cloud Native**: Direct support for IAM authentication without proxies
3. **Flexibility**: Works with any token/password provider (OAuth2, Vault, AWS IAM, etc.)
4. **Simplicity**: Clean API that doesn't break existing code
5. **Performance**: No overhead for users not using these features

## Migration Guide

For existing Postgrex users wanting to adopt IAM authentication:

1. Replace `:password` with `:password_provider` in your configuration
2. Implement a token provider function or module
3. Enable SSL with `:ssl_profile` for secure connections
4. No other changes required!

## Future Enhancements

Potential future improvements:
- Token caching with TTL support
- Automatic token refresh before expiry
- Built-in providers for common cloud platforms
- Telemetry events for auth failures/retries