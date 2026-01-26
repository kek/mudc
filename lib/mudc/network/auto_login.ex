defmodule Mudc.Network.AutoLogin do
  @moduledoc """
  Handles automatic login by watching for login prompts and sending credentials
  from environment variables.

  Subscribes to :game_text events and watches for:
  - "By what name do you wish to be known?" -> sends $USERNAME
  - "Account password:" -> sends $PASSWORD
  """

  use GenServer
  require Logger

  alias Mudc.Config.Manager, as: Config
  alias Mudc.Events.Bus
  alias Mudc.Network.Connection

  defstruct [:has_credentials, :sent_username, :sent_password]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to game text events
    Bus.subscribe(:game_text)

    # Check if credentials are available without storing them
    has_credentials = has_credentials?()

    state = %__MODULE__{
      has_credentials: has_credentials,
      sent_username: false,
      sent_password: false
    }

    if has_credentials do
      Logger.debug("AutoLogin: Credentials are configured")
    end

    {:ok, state}
  end

  @impl true
  def handle_info({:event, :game_text, {:text, text}}, state) do
    state = check_for_prompts(text, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :game_text, _other}, state) do
    # Ignore non-text events like :prompt
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  # Fetch credentials on-demand instead of storing in state
  defp get_credential(:username), do: System.get_env("USERNAME")
  defp get_credential(:password), do: System.get_env("PASSWORD")

  defp has_credentials? do
    not is_nil(System.get_env("USERNAME")) and not is_nil(System.get_env("PASSWORD"))
  end

  defp matches_name_prompt?(text) do
    prompt = Config.get(:auto_login, :name_prompt) || "By what name do you wish to be known?"
    String.contains?(text, prompt)
  end

  defp matches_password_prompt?(text) do
    prompt = Config.get(:auto_login, :password_prompt) || "Account password:"
    String.contains?(text, prompt)
  end

  defp check_for_prompts(text, state) do
    state
    |> maybe_send_username(text)
    |> maybe_send_password(text)
  end

  defp maybe_send_username(state, text) do
    cond do
      state.sent_username ->
        # Already sent username
        state

      not state.has_credentials ->
        # No credentials configured
        state

      matches_name_prompt?(text) ->
        # Fetch username on-demand when needed
        username = get_credential(:username)

        if username do
          Logger.info("AutoLogin: Detected name prompt, sending username")
          Connection.send_command(username)
          %{state | sent_username: true}
        else
          state
        end

      true ->
        state
    end
  end

  defp maybe_send_password(state, text) do
    cond do
      state.sent_password ->
        # Already sent password
        state

      not state.has_credentials ->
        # No credentials configured
        state

      matches_password_prompt?(text) ->
        # Fetch password on-demand when needed
        password = get_credential(:password)

        if password do
          Logger.info("AutoLogin: Detected password prompt, sending password")
          Connection.send_command(password)
          %{state | sent_password: true}
        else
          state
        end

      true ->
        state
    end
  end
end
