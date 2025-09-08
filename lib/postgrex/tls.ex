defmodule Postgrex.TLS do
  @moduledoc """
  TLS configuration helpers for Postgrex connections.

  This module provides secure TLS configuration profiles for
  connecting to PostgreSQL servers, particularly useful for
  cloud providers and IAM-based authentication.
  """

  @doc """
  Returns TLS options with strict server certificate verification.

  This profile:
  - Enables server certificate verification
  - Uses system CA certificates
  - Sets Server Name Indication (SNI) for proper certificate validation
  - Enables hostname verification

  ## Examples

      iex> Postgrex.TLS.strict_opts!("db.example.com")
      [
        verify: :verify_peer,
        cacerts: [...],  # System CAs
        server_name_indication: 'db.example.com',
        customize_hostname_check: [...]
      ]

      # With overrides
      iex> Postgrex.TLS.strict_opts!("db.example.com", depth: 3)
      [
        verify: :verify_peer,
        cacerts: [...],
        server_name_indication: 'db.example.com',
        customize_hostname_check: [...],
        depth: 3
      ]
  """
  @spec strict_opts!(String.t(), Keyword.t()) :: Keyword.t()
  def strict_opts!(hostname, overrides \\ []) when is_binary(hostname) do
    base_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(hostname),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    Keyword.merge(base_opts, overrides)
  end

  @doc """
  Returns TLS options optimized for cloud providers.

  Similar to `strict_opts!/2` but with additional defaults
  commonly needed for cloud database services:
  - Higher certificate chain depth (for intermediate CAs)
  - Compatible cipher suites

  ## Examples

      iex> Postgrex.TLS.cloud_opts!("project.region.alloydb.goog")
      [
        verify: :verify_peer,
        cacerts: [...],
        server_name_indication: 'project.region.alloydb.goog',
        customize_hostname_check: [...],
        depth: 3
      ]
  """
  @spec cloud_opts!(String.t(), Keyword.t()) :: Keyword.t()
  def cloud_opts!(hostname, overrides \\ []) when is_binary(hostname) do
    base_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(hostname),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ],
      depth: 3
    ]

    Keyword.merge(base_opts, overrides)
  end

  @doc false
  def apply_profile(nil, ssl_opts, _hostname), do: ssl_opts

  def apply_profile(:strict, nil, hostname) when is_binary(hostname) do
    strict_opts!(hostname)
  end

  def apply_profile(:cloud, nil, hostname) when is_binary(hostname) do
    cloud_opts!(hostname)
  end

  def apply_profile(_profile, ssl_opts, _hostname) when is_list(ssl_opts) do
    # If ssl_opts are explicitly provided, ignore the profile
    ssl_opts
  end
end