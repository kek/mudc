defmodule Mudc.Config.CookieManagerTest do
  # File I/O requires sequential execution
  use ExUnit.Case, async: false

  import Bitwise

  alias Mudc.Config.CookieManager

  @test_dir System.tmp_dir!() |> Path.join("mudc_cookie_test")

  setup do
    # Clean test directory
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    # Override config directory for tests
    Application.put_env(:mudc, :config_dir, @test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
      Application.delete_env(:mudc, :config_dir)
    end)

    :ok
  end

  describe "get_cookie/0" do
    test "generates new cookie if none exists" do
      assert {:ok, cookie} = CookieManager.get_cookie()
      assert is_binary(cookie)
      assert byte_size(cookie) > 20
    end

    test "returns existing cookie if present" do
      {:ok, cookie1} = CookieManager.get_cookie()
      {:ok, cookie2} = CookieManager.get_cookie()
      assert cookie1 == cookie2
    end

    test "regenerates if cookie file has wrong permissions" do
      path = CookieManager.cookie_path()
      File.write!(path, "test_cookie_that_is_long_enough_to_pass_validation")
      # Too permissive
      File.chmod!(path, 0o644)

      assert {:ok, new_cookie} = CookieManager.get_cookie()
      assert new_cookie != "test_cookie_that_is_long_enough_to_pass_validation"
    end

    test "regenerates if cookie file is corrupted" do
      path = CookieManager.cookie_path()
      # Too short
      File.write!(path, "bad")

      assert {:ok, new_cookie} = CookieManager.get_cookie()
      assert byte_size(new_cookie) > 20
    end
  end

  describe "regenerate_cookie/0" do
    test "creates new cookie" do
      assert {:ok, cookie} = CookieManager.regenerate_cookie()
      assert is_binary(cookie)
    end

    test "overwrites existing cookie" do
      {:ok, cookie1} = CookieManager.get_cookie()
      {:ok, cookie2} = CookieManager.regenerate_cookie()
      assert cookie1 != cookie2
    end
  end

  describe "cookie format" do
    test "generates base64 encoded strings" do
      {:ok, cookie} = CookieManager.get_cookie()
      assert String.match?(cookie, ~r/^[A-Za-z0-9+\/\-_]+$/)
    end

    test "cookies are different on each generation" do
      {:ok, cookie1} = CookieManager.regenerate_cookie()
      {:ok, cookie2} = CookieManager.regenerate_cookie()
      assert cookie1 != cookie2
    end
  end

  describe "file permissions" do
    test "sets 0600 permissions on creation" do
      CookieManager.get_cookie()
      path = CookieManager.cookie_path()

      {:ok, stat} = File.stat(path)
      assert (stat.mode &&& 0o777) == 0o600
    end
  end

  describe "error handling" do
    test "handles corrupted cookie files gracefully" do
      path = CookieManager.cookie_path()
      # Binary garbage
      File.write!(path, <<0, 1, 2>>)

      assert {:ok, _cookie} = CookieManager.get_cookie()
    end
  end
end
