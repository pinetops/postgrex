defmodule ConfigResolverTest do
  use ExUnit.Case
  alias Postgrex, as: P
  import ExUnit.CaptureLog

  setup do
    {:ok, [options: [database: "postgrex_test", backoff_type: :stop, max_restarts: 0]]}
  end

  describe "config_resolver functionality" do
    test "config_resolver function is called during connection", context do
      # Use a reference to track if resolver was called
      test_pid = self()
      resolver_called_ref = make_ref()

      resolver = fn opts ->
        send(test_pid, {:resolver_called, resolver_called_ref, Keyword.keys(opts)})
        opts
      end

      opts = [config_resolver: resolver] ++ context[:options]
      assert {:ok, pid} = P.start_link(opts)
      assert {:ok, %Postgrex.Result{}} = P.query(pid, "SELECT 1", [])

      # Verify resolver was called
      assert_receive {:resolver_called, ^resolver_called_ref, option_keys}
      
      # Verify expected options were passed to resolver
      assert :database in option_keys
      assert :types in option_keys
      refute :config_resolver in option_keys  # Should be removed before calling resolver
    end

    test "config_resolver can modify connection options", context do
      test_pid = self()
      original_db = "original_database"
      modified_db = context[:options][:database]  # Use the test database

      resolver = fn opts ->
        send(test_pid, {:original_db, opts[:database]})
        Keyword.put(opts, :database, modified_db)
      end

      opts = [
        config_resolver: resolver, 
        database: original_db
      ] ++ Keyword.delete(context[:options], :database)

      assert {:ok, pid} = P.start_link(opts)
      assert {:ok, %Postgrex.Result{}} = P.query(pid, "SELECT 1", [])

      # Verify original database name was passed to resolver
      assert_receive {:original_db, ^original_db}
    end

    test "config_resolver can add missing options", context do
      resolver = fn opts ->
        opts
        |> Keyword.put_new(:username, "postgres") 
        |> Keyword.put_new(:password, "")
        |> Keyword.put(:connect_timeout, 5000)
      end

      # Start without explicit username/password, let resolver add them
      opts = [config_resolver: resolver] ++ context[:options]
      assert {:ok, pid} = P.start_link(opts)
      assert {:ok, %Postgrex.Result{}} = P.query(pid, "SELECT 1", [])
    end

    test "config_resolver receives all connection options except itself", context do
      test_pid = self()
      
      resolver = fn opts ->
        send(test_pid, {:all_opts, opts})
        opts
      end

      input_opts = [
        hostname: "localhost",
        port: 5432,
        database: context[:options][:database],
        username: "postgres", 
        password: "",
        ssl: false,
        timeout: 15_000,
        config_resolver: resolver
      ] ++ Keyword.drop(context[:options], [:database])

      assert {:ok, _pid} = P.start_link(input_opts)
      
      assert_receive {:all_opts, received_opts}
      
      # Verify config_resolver was removed
      refute Keyword.has_key?(received_opts, :config_resolver)
      
      # Verify other options were passed through
      assert received_opts[:hostname] == "localhost"
      assert received_opts[:port] == 5432
      assert received_opts[:database] == context[:options][:database]
      assert received_opts[:username] == "postgres"
      assert received_opts[:timeout] == 15_000
    end
  end

  describe "config_resolver error handling" do
    test "rejects non-function config_resolver", context do
      invalid_resolvers = [
        "not_a_function",
        :atom,
        123,
        %{not: :function},
        ["not", "function"]
      ]

      for invalid_resolver <- invalid_resolvers do
        assert capture_log(fn ->
                 opts = [config_resolver: invalid_resolver] ++ context[:options]
                 assert_start_and_killed(opts)
               end) =~ "ArgumentError"
      end
    end

    test "rejects config_resolver with wrong arity", context do
      wrong_arity_resolvers = [
        fn -> :no_args end,
        fn _arg1, _arg2 -> :two_args end,
        fn _arg1, _arg2, _arg3 -> :three_args end
      ]

      for wrong_resolver <- wrong_arity_resolvers do
        assert capture_log(fn ->
                 opts = [config_resolver: wrong_resolver] ++ context[:options]
                 assert_start_and_killed(opts)
               end) =~ "ArgumentError"
      end
    end

    test "handles config_resolver that raises exceptions", context do
      failing_resolver = fn _opts ->
        raise "Resolver failed!"
      end

      assert capture_log(fn ->
               opts = [config_resolver: failing_resolver] ++ context[:options]
               assert_start_and_killed(opts)
             end) =~ "Resolver failed!"
    end

    test "handles config_resolver returning invalid options", context do
      invalid_return_resolver = fn _opts ->
        "not a keyword list"
      end

      assert capture_log(fn ->
               opts = [config_resolver: invalid_return_resolver] ++ context[:options]
               assert_start_and_killed(opts)
             end)
    end
  end

  describe "config_resolver with different connection scenarios" do
    test "works with SSL options", context do
      test_pid = self()
      
      resolver = fn opts ->
        send(test_pid, {:ssl_opts, opts[:ssl]})
        Keyword.put(opts, :ssl, false)  # Ensure SSL is disabled for test
      end

      opts = [
        config_resolver: resolver,
        ssl: true  # This should be overridden by resolver
      ] ++ context[:options]

      assert {:ok, pid} = P.start_link(opts)
      assert {:ok, %Postgrex.Result{}} = P.query(pid, "SELECT 1", [])

      # Verify resolver received the original SSL setting
      assert_receive {:ssl_opts, true}
    end

    test "works with parameters option", context do
      test_pid = self()
      original_params = [application_name: "original_app"]
      
      resolver = fn opts ->
        send(test_pid, {:original_params, opts[:parameters]})
        Keyword.put(opts, :parameters, [application_name: "resolved_app"])
      end

      opts = [
        config_resolver: resolver,
        parameters: original_params
      ] ++ context[:options]

      assert {:ok, pid} = P.start_link(opts)
      assert {:ok, %Postgrex.Result{}} = P.query(pid, "SELECT 1", [])

      # Verify parameters were passed through resolver
      assert_receive {:original_params, ^original_params}
      
      # Verify the resolved parameters are in effect
      assert P.parameters(pid)["application_name"] == "resolved_app"
    end

    test "works with timeout options", context do
      resolver = fn opts ->
        opts
        |> Keyword.put(:connect_timeout, 10_000)
        |> Keyword.put(:timeout, 20_000)
      end

      opts = [
        config_resolver: resolver,
        connect_timeout: 1000,  # Should be overridden
        timeout: 2000          # Should be overridden
      ] ++ context[:options]

      assert {:ok, pid} = P.start_link(opts)
      assert {:ok, %Postgrex.Result{}} = P.query(pid, "SELECT 1", [])
    end

    @tag :unix
    test "works with socket options", context do
      socket_dir = System.get_env("PG_SOCKET_DIR") || "/tmp"
      
      resolver = fn opts ->
        Keyword.put(opts, :socket_dir, socket_dir)
      end

      opts = [
        config_resolver: resolver,
        hostname: "will_be_ignored"  # Socket should take precedence
      ] ++ context[:options]

      capture_log(fn ->
        assert {:ok, pid} = P.start_link(opts)
        assert {:ok, %Postgrex.Result{}} = P.query(pid, "SELECT 1", [])
      end)
    end
  end

  describe "config_resolver and connection retries" do
    test "config_resolver is called on each connection attempt", context do
      test_pid = self()
      call_count_ref = :counters.new(1, [])
      
      resolver = fn opts ->
        count = :counters.add(call_count_ref, 1, 1)
        send(test_pid, {:resolver_call, count})
        
        # First call: use wrong port to force retry
        # Second call: use correct port
        port = if count == 1, do: 9999, else: 5432
        Keyword.put(opts, :port, port)
      end

      opts = [
        config_resolver: resolver,
        connect_timeout: 500,
        backoff_type: :exp,
        backoff_min: 100,
        backoff_max: 1000,
        max_restarts: 2
      ] ++ context[:options]

      # This should eventually succeed after retry
      assert {:ok, pid} = P.start_link(opts)
      assert {:ok, %Postgrex.Result{}} = P.query(pid, "SELECT 1", [])

      # Verify resolver was called multiple times
      assert_receive {:resolver_call, 1}
      assert_receive {:resolver_call, 2}
    end
  end

  # Helper function from login_test.exs
  defp assert_start_and_killed(opts) do
    Process.flag(:trap_exit, true)

    case P.start_link(opts) do
      {:ok, pid} -> assert_receive {:EXIT, ^pid, :killed}, 5_000
      {:error, :killed} -> :ok
    end
  end
end