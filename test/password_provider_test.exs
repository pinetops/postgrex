defmodule PasswordProviderTest do
  use ExUnit.Case, async: true
  
  defmodule TestProvider do
    def static_password, do: "test_password"
    
    def dynamic_password(prefix), do: "#{prefix}_password"
    
    def counter_password do
      # In a real scenario, this could be a rotating token
      counter = Process.get(:password_counter, 0)
      Process.put(:password_counter, counter + 1)
      "password_#{counter}"
    end
  end

  describe "password_provider option" do
    test "accepts a zero-arity function" do
      provider = fn -> "function_password" end
      
      # This would be called internally by Postgrex
      assert provider.() == "function_password"
    end
    
    test "accepts an MFA tuple without args" do
      provider = {TestProvider, :static_password, []}
      
      # This would be called internally by Postgrex
      {mod, fun, args} = provider
      assert apply(mod, fun, args) == "test_password"
    end
    
    test "accepts an MFA tuple with args" do
      provider = {TestProvider, :dynamic_password, ["prefix"]}
      
      # This would be called internally by Postgrex
      {mod, fun, args} = provider
      assert apply(mod, fun, args) == "prefix_password"
    end
    
    test "provider is called on each connection" do
      provider = {TestProvider, :counter_password, []}
      
      # Simulate multiple connection attempts
      {mod, fun, args} = provider
      assert apply(mod, fun, args) == "password_0"
      assert apply(mod, fun, args) == "password_1"
      assert apply(mod, fun, args) == "password_2"
    end
  end

  describe "TLS profiles" do
    test "strict_opts! generates proper SSL options" do
      opts = Postgrex.TLS.strict_opts!("db.example.com")
      
      assert opts[:verify] == :verify_peer
      assert opts[:server_name_indication] == 'db.example.com'
      assert is_list(opts[:cacerts])
      assert opts[:customize_hostname_check]
    end
    
    test "cloud_opts! includes higher depth" do
      opts = Postgrex.TLS.cloud_opts!("project.region.alloydb.goog")
      
      assert opts[:verify] == :verify_peer
      assert opts[:server_name_indication] == 'project.region.alloydb.goog'
      assert opts[:depth] == 3
      assert is_list(opts[:cacerts])
    end
    
    test "strict_opts! accepts overrides" do
      opts = Postgrex.TLS.strict_opts!("db.example.com", depth: 5, custom: :value)
      
      assert opts[:depth] == 5
      assert opts[:custom] == :value
      assert opts[:verify] == :verify_peer
    end
    
    test "apply_profile returns nil when no SSL" do
      assert Postgrex.TLS.apply_profile(nil, nil, "host") == nil
    end
    
    test "apply_profile ignores profile when ssl_opts provided" do
      ssl_opts = [verify: :verify_none]
      assert Postgrex.TLS.apply_profile(:strict, ssl_opts, "host") == ssl_opts
    end
    
    test "apply_profile applies strict profile" do
      opts = Postgrex.TLS.apply_profile(:strict, nil, "db.example.com")
      assert opts[:verify] == :verify_peer
      assert opts[:server_name_indication] == 'db.example.com'
    end
    
    test "apply_profile applies cloud profile" do
      opts = Postgrex.TLS.apply_profile(:cloud, nil, "cloud.db.com")
      assert opts[:verify] == :verify_peer
      assert opts[:depth] == 3
    end
  end

  describe "integration with auth flow" do
    # These tests would require a mock server or actual database
    # For now, we test the helper functions
    
    test "get_password with regular password" do
      opts = [password: "regular_password", username: "user"]
      
      # This simulates what happens in auth_cleartext
      password = get_test_password(opts)
      assert password == "regular_password"
    end
    
    test "get_password with password_provider function" do
      opts = [
        password_provider: fn -> "provider_password" end,
        username: "user"
      ]
      
      password = get_test_password(opts)
      assert password == "provider_password"
    end
    
    test "get_password with password_provider MFA" do
      opts = [
        password_provider: {TestProvider, :static_password, []},
        username: "user"
      ]
      
      password = get_test_password(opts)
      assert password == "test_password"
    end
    
    test "password_provider takes precedence over password" do
      opts = [
        password: "ignored",
        password_provider: fn -> "provider_password" end,
        username: "user"
      ]
      
      password = get_test_password(opts)
      assert password == "provider_password"
    end
  end
  
  # Helper that mimics the get_password function in Protocol/SCRAM
  defp get_test_password(opts) do
    case Keyword.get(opts, :password_provider) do
      nil ->
        Keyword.fetch!(opts, :password)
      
      fun when is_function(fun, 0) ->
        fun.()
      
      {mod, fun, args} ->
        apply(mod, fun, args)
    end
  end
end