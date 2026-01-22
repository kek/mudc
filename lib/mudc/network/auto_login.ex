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

  alias Mudc.Events.Bus
  alias Mudc.Network.Connection

  @name_prompt "By what name do you wish to be known?"
  @password_prompt "Account password:"

  defstruct [:username, :password, :sent_username, :sent_password]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to game text events
    Bus.subscribe(:game_text)

    state = %__MODULE__{
      username: System.get_env("USERNAME"),
      password: System.get_env("PASSWORD"),
      sent_username: false,
      sent_password: false
    }

    if state.username do
      Logger.debug("AutoLogin: USERNAME environment variable is set")
    end

    if state.password do
      Logger.debug("AutoLogin: PASSWORD environment variable is set")
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

      is_nil(state.username) ->
        # No username configured
        state

      String.contains?(text, @name_prompt) ->
        Logger.info("AutoLogin: Detected name prompt, sending username")
        Connection.send_command(state.username)
        %{state | sent_username: true}

      true ->
        state
    end
  end

  defp maybe_send_password(state, text) do
    cond do
      state.sent_password ->
        # Already sent password
        state

      is_nil(state.password) ->
        # No password configured
        state

      String.contains?(text, @password_prompt) ->
        Logger.info("AutoLogin: Detected password prompt, sending password")
        Connection.send_command(state.password)
        %{state | sent_password: true}

      true ->
        state
    end
  end
end
