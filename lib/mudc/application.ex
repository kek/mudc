defmodule Mudc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Note: UI is started via mix task or manually, not supervised here
      # See Mudc.UI.Terminal for details
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mudc.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
