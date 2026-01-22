defmodule Mudc.Telnet.ConnectionConfig do
  @moduledoc """
  Configuration struct for Telnet connections.

  Defines connection parameters with sensible defaults for connecting
  to MMapper/MUME via WSL to Windows host.
  """

  @type t :: %__MODULE__{
          host: String.t(),
          port: :inet.port_number(),
          timeout: non_neg_integer(),
          active: boolean()
        }

  defstruct host: "172.24.0.1",
            port: 4242,
            timeout: 5000,
            active: true

  @doc """
  Creates a new ConnectionConfig with optional overrides.

  ## Examples

      iex> config = Mudc.Telnet.ConnectionConfig.new()
      iex> config.host
      "172.24.0.1"

      iex> config = Mudc.Telnet.ConnectionConfig.new(port: 4000)
      iex> config.port
      4000
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end
end
