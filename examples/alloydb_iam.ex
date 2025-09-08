defmodule AlloyDBExample do
  @moduledoc """
  Example of connecting to AlloyDB using IAM authentication with Postgrex.

  This demonstrates using the new password_provider and ssl_profile options
  to connect to Google Cloud AlloyDB without hardcoded passwords.
  """

  @doc """
  Example IAM token provider module.
  
  In production, this would use Google Cloud SDK or service account credentials
  to generate OAuth2 access tokens.
  """
  defmodule IAMTokenProvider do
    @doc """
    Generates a fresh OAuth2 access token for AlloyDB authentication.
    
    This is called by Postgrex on each (re)connect, ensuring fresh tokens
    even for long-lived connections.
    """
    def get_access_token do
      # In real implementation, this would:
      # 1. Use Application Default Credentials (ADC)
      # 2. Or read from service account JSON
      # 3. Exchange for an access token with proper scopes
      
      case System.cmd("gcloud", ["auth", "print-access-token"]) do
        {token, 0} -> String.trim(token)
        _ -> raise "Failed to obtain access token"
      end
    end

    @doc """
    Alternative implementation using a library like Goth.
    """
    def get_access_token_with_goth do
      {:ok, %{token: token}} = Goth.fetch(MyApp.Goth)
      token
    end
  end

  @doc """
  Direct connection to AlloyDB using IAM authentication.
  
  No proxy required - connects directly to the AlloyDB instance.
  """
  def connect_direct do
    opts = [
      hostname: System.fetch_env!("ALLOYDB_HOST"),  # e.g., "10.x.x.x" or "project.region.alloydb.goog"
      database: System.fetch_env!("ALLOYDB_DATABASE"),
      username: System.fetch_env!("IAM_DB_USER"),  # e.g., "user@example.com"
      
      # Use password_provider instead of password
      password_provider: {IAMTokenProvider, :get_access_token, []},
      
      # Enable SSL with strict verification
      ssl: true,
      ssl_profile: :cloud,  # Optimized for cloud providers
      
      # Connection pool settings
      pool_size: 10,
      
      # Recommended timeouts
      timeout: 15_000,
      connect_timeout: 10_000,
      handshake_timeout: 10_000
    ]
    
    Postgrex.start_link(opts)
  end

  @doc """
  Connection using a zero-argument function as password provider.
  """
  def connect_with_function do
    opts = [
      hostname: System.fetch_env!("ALLOYDB_HOST"),
      database: System.fetch_env!("ALLOYDB_DATABASE"),
      username: System.fetch_env!("IAM_DB_USER"),
      
      # Using an anonymous function
      password_provider: fn ->
        IAMTokenProvider.get_access_token()
      end,
      
      ssl: true,
      ssl_profile: :strict,
      
      pool_size: 10
    ]
    
    Postgrex.start_link(opts)
  end

  @doc """
  Example with custom SSL options while still using password_provider.
  """
  def connect_with_custom_ssl do
    hostname = System.fetch_env!("ALLOYDB_HOST")
    
    opts = [
      hostname: hostname,
      database: System.fetch_env!("ALLOYDB_DATABASE"),
      username: System.fetch_env!("IAM_DB_USER"),
      
      password_provider: {IAMTokenProvider, :get_access_token, []},
      
      # Manual SSL configuration (overrides ssl_profile)
      ssl: Postgrex.TLS.cloud_opts!(hostname, 
        # Additional custom options
        versions: [:"tlsv1.3", :"tlsv1.2"],
        ciphers: :ssl.cipher_suites(:all, :"tlsv1.3")
      ),
      
      pool_size: 10
    ]
    
    Postgrex.start_link(opts)
  end

  @doc """
  Example Ecto configuration for AlloyDB with IAM.
  
  Add this to your config/runtime.exs or config/prod.exs:
  """
  def ecto_config_example do
    """
    config :my_app, MyApp.Repo,
      adapter: Ecto.Adapters.Postgres,
      hostname: System.fetch_env!("ALLOYDB_HOST"),
      database: System.fetch_env!("ALLOYDB_DATABASE"),
      username: System.fetch_env!("IAM_DB_USER"),
      
      # IAM token provider
      password_provider: {AlloyDBExample.IAMTokenProvider, :get_access_token, []},
      
      # TLS configuration
      ssl: true,
      ssl_profile: :cloud,
      
      # Pool configuration
      pool_size: 10,
      queue_target: 50,
      queue_interval: 100,
      
      # Timeouts
      timeout: 15_000,
      connect_timeout: 10_000,
      handshake_timeout: 10_000
    """
  end

  @doc """
  Example with HashiCorp Vault for password rotation.
  """
  defmodule VaultProvider do
    def get_database_password do
      # Read from Vault
      {:ok, %{"data" => %{"password" => password}}} = 
        Vault.read("database/creds/myapp")
      
      password
    end
  end

  def connect_with_vault do
    opts = [
      hostname: "localhost",
      database: "myapp",
      username: "vault_user",
      
      # Vault provides rotating passwords
      password_provider: {VaultProvider, :get_database_password, []},
      
      ssl: false,
      pool_size: 10
    ]
    
    Postgrex.start_link(opts)
  end

  @doc """
  Example for AWS RDS with IAM authentication.
  """
  defmodule AWSRDSProvider do
    def get_auth_token do
      # Generate RDS IAM auth token
      # This would use ExAws or AWS SDK
      region = "us-east-1"
      hostname = "mydb.123456789012.us-east-1.rds.amazonaws.com"
      port = 5432
      username = "iam_user"
      
      # In practice, use AWS SDK to generate the token
      generate_rds_iam_token(region, hostname, port, username)
    end
    
    defp generate_rds_iam_token(_region, _hostname, _port, _username) do
      # Placeholder - would use AWS SDK
      "rds-iam-token"
    end
  end

  def connect_to_rds_iam do
    hostname = "mydb.123456789012.us-east-1.rds.amazonaws.com"
    
    opts = [
      hostname: hostname,
      port: 5432,
      database: "postgres",
      username: "iam_user",
      
      password_provider: {AWSRDSProvider, :get_auth_token, []},
      
      ssl: true,
      ssl_profile: :strict,  # RDS provides valid certificates
      
      pool_size: 10
    ]
    
    Postgrex.start_link(opts)
  end
end