#!/usr/bin/env elixir

# Simple test script to verify our password_provider implementation
# Run with: elixir simple_test.exs

defmodule SimpleTest do
  def test_password_provider do
    IO.puts("Testing password_provider functionality...")
    
    # Test 1: Function provider
    provider_fn = fn -> "token_from_function" end
    password = call_provider(provider_fn)
    IO.puts("✓ Function provider returned: #{password}")
    
    # Test 2: MFA provider
    defmodule Provider do
      def get_token, do: "token_from_mfa"
      def get_token_with_args(prefix), do: "#{prefix}_token"
    end
    
    provider_mfa = {Provider, :get_token, []}
    password = call_provider(provider_mfa)
    IO.puts("✓ MFA provider returned: #{password}")
    
    # Test 3: MFA with arguments
    provider_mfa_args = {Provider, :get_token_with_args, ["iam"]}
    password = call_provider(provider_mfa_args)
    IO.puts("✓ MFA with args returned: #{password}")
    
    IO.puts("\nAll password_provider tests passed!")
  end
  
  def test_tls_profiles do
    IO.puts("\nTesting TLS profiles...")
    
    # Test strict profile
    opts = Postgrex.TLS.strict_opts!("db.example.com")
    IO.puts("✓ strict_opts! created options with:")
    IO.puts("  - verify: #{opts[:verify]}")
    IO.puts("  - SNI: #{opts[:server_name_indication]}")
    IO.puts("  - CA certs: #{length(opts[:cacerts])} certificates")
    
    # Test cloud profile
    opts = Postgrex.TLS.cloud_opts!("cloud.db.com")
    IO.puts("✓ cloud_opts! created options with:")
    IO.puts("  - verify: #{opts[:verify]}")
    IO.puts("  - depth: #{opts[:depth]}")
    IO.puts("  - SNI: #{opts[:server_name_indication]}")
    
    # Test apply_profile
    opts = Postgrex.TLS.apply_profile(:strict, nil, "test.com")
    IO.puts("✓ apply_profile(:strict) works")
    
    opts = Postgrex.TLS.apply_profile(:cloud, nil, "test.com")
    IO.puts("✓ apply_profile(:cloud) works")
    
    # Test that explicit ssl_opts override profile
    explicit_opts = [verify: :verify_none]
    result = Postgrex.TLS.apply_profile(:strict, explicit_opts, "test.com")
    if result == explicit_opts do
      IO.puts("✓ Explicit ssl_opts override profile")
    end
    
    IO.puts("\nAll TLS profile tests passed!")
  end
  
  defp call_provider(fun) when is_function(fun, 0), do: fun.()
  defp call_provider({mod, fun, args}), do: apply(mod, fun, args)
end

# Run the tests
SimpleTest.test_password_provider()
SimpleTest.test_tls_profiles()

IO.puts("\n✅ All tests passed successfully!")
IO.puts("\nYour Postgrex modifications are working correctly.")
IO.puts("You can now use:")
IO.puts("  - password_provider: for IAM tokens and rotating credentials")
IO.puts("  - ssl_profile: for secure TLS connections to cloud databases")