defmodule Mix.Tasks.CookieIntegrationTest do
  use ExUnit.Case, async: false

  alias Mudc.Config.CookieManager

  @test_dir System.tmp_dir!() |> Path.join("mudc_integration_test")

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)
    Application.put_env(:mudc, :config_dir, @test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
      Application.delete_env(:mudc, :config_dir)
    end)

    :ok
  end

  test "cookie persists across multiple get_cookie calls" do
    {:ok, cookie1} = CookieManager.get_cookie()
    {:ok, cookie2} = CookieManager.get_cookie()
    {:ok, cookie3} = CookieManager.get_cookie()

    assert cookie1 == cookie2
    assert cookie2 == cookie3
  end

  test "cookie file exists at expected location" do
    CookieManager.get_cookie()

    path = CookieManager.cookie_path()
    assert File.exists?(path)
  end
end
