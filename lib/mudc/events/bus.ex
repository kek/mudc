defmodule Mudc.Events.Bus do
  @moduledoc """
  Registry-based PubSub event bus for decoupled communication between components.

  Events are published to topics and all subscribers receive the messages.
  Uses Elixir's Registry for efficient dispatch.

  ## Example

      # Subscribe to game text events
      Mudc.Events.Bus.subscribe(:game_text)

      # Publish game text
      Mudc.Events.Bus.publish(:game_text, {:text, "Welcome to MUME!"})

      # Subscriber receives: {:event, :game_text, {:text, "Welcome to MUME!"}}
  """

  @registry __MODULE__

  @doc """
  Returns the child spec for starting the registry under a supervisor.
  """
  def child_spec(_opts) do
    Registry.child_spec(keys: :duplicate, name: @registry)
  end

  @doc """
  Subscribe the calling process to a topic.
  """
  def subscribe(topic) do
    {:ok, _} = Registry.register(@registry, topic, [])
    :ok
  end

  @doc """
  Unsubscribe the calling process from a topic.
  """
  def unsubscribe(topic) do
    Registry.unregister(@registry, topic)
  end

  @doc """
  Publish a message to all subscribers of a topic.
  """
  def publish(topic, message) do
    Registry.dispatch(@registry, topic, fn entries ->
      for {pid, _} <- entries do
        send(pid, {:event, topic, message})
      end
    end)
  end

  @doc """
  Returns the number of subscribers for a topic.
  """
  def subscriber_count(topic) do
    Registry.count_match(@registry, topic, :_)
  end
end
