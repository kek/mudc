defmodule Mudc.Config.CookieManager do
  @moduledoc """
  Manages Erlang distribution cookies for secure remote REPL access.

  Generates secure random cookies and stores them in ~/.config/mudc/.erlang.cookie
  with proper file permissions (0600). Reuses existing cookies if present.
  """

  import Bitwise

  @cookie_filename ".erlang.cookie"
  @default_config_dir "~/.config/mudc"

  @doc """
  Gets existing cookie or generates new one.
  Returns {:ok, cookie_string} or {:error, reason}.
  """
  def get_cookie do
    cookie_path = cookie_path()

    case load_cookie(cookie_path) do
      {:ok, cookie} ->
        {:ok, cookie}

      {:error, :not_found} ->
        generate_and_store_cookie(cookie_path)

      {:error, :invalid_permissions} ->
        generate_and_store_cookie(cookie_path)

      {:error, :corrupted} ->
        generate_and_store_cookie(cookie_path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Forces regeneration of cookie.
  """
  def regenerate_cookie do
    generate_and_store_cookie(cookie_path())
  end

  @doc """
  Returns the path to the cookie file.
  """
  def cookie_path do
    config_dir = Application.get_env(:mudc, :config_dir, @default_config_dir)
    Path.expand(Path.join(config_dir, @cookie_filename))
  end

  # Private functions

  defp generate_and_store_cookie(path) do
    cookie = generate_random_cookie()

    case store_cookie(path, cookie) do
      :ok -> {:ok, cookie}
      error -> error
    end
  end

  defp generate_random_cookie do
    :crypto.strong_rand_bytes(32)
    |> Base.encode64(padding: false)
  end

  defp load_cookie(path) do
    if not File.exists?(path) do
      {:error, :not_found}
    else
      with {:ok, _perms} <- verify_permissions(path),
           {:ok, cookie} <- File.read(path),
           true <- valid_cookie?(cookie) do
        {:ok, String.trim(cookie)}
      else
        {:error, :bad_permissions} -> {:error, :invalid_permissions}
        {:error, _} = error -> error
        false -> {:error, :corrupted}
      end
    end
  end

  defp store_cookie(path, cookie) do
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, cookie),
         :ok <- set_secure_permissions(path) do
      :ok
    else
      error -> error
    end
  end

  defp verify_permissions(path) do
    case File.stat(path) do
      {:ok, %{mode: mode}} ->
        # Check if mode is 0600 (owner read/write only)
        if (mode &&& 0o777) == 0o600 do
          {:ok, :secure}
        else
          {:error, :bad_permissions}
        end

      error ->
        error
    end
  end

  defp set_secure_permissions(path) do
    # Set to 0600 (owner read/write only)
    case :file.change_mode(String.to_charlist(path), 0o600) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_cookie?(cookie) when is_binary(cookie) do
    trimmed = String.trim(cookie)
    byte_size(trimmed) > 20 and byte_size(trimmed) < 100
  end

  defp valid_cookie?(_), do: false
end
