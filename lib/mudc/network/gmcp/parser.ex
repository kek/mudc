defmodule Mudc.Network.GMCP.Parser do
  @moduledoc """
  Pure GMCP message parser.

  GMCP messages have the format: `Package.Name {json_data}`
  where the JSON data is optional.

  ## Example

      {:ok, package, data} = Parser.parse("Char.Vitals {\"hp\":100}")
      # package = "Char.Vitals"
      # data = %{"hp" => 100}

      {:ok, package, nil} = Parser.parse("Core.Ping")
      # package = "Core.Ping"
      # data = nil
  """

  @doc """
  Parse a GMCP message into package name and optional JSON data.
  """
  @spec parse(binary()) :: {:ok, String.t(), term()} | {:error, term()}
  def parse(message) when is_binary(message) do
    message = String.trim(message)

    case String.split(message, " ", parts: 2) do
      [package] ->
        {:ok, package, nil}

      [package, json_str] ->
        case Jason.decode(json_str) do
          {:ok, data} ->
            {:ok, package, data}

          {:error, reason} ->
            {:error, {:json_decode_error, reason, json_str}}
        end
    end
  end

  @doc """
  Encode a GMCP message from package name and data.
  """
  @spec encode(String.t(), term()) :: binary()
  def encode(package, nil), do: package

  def encode(package, data) do
    json = Jason.encode!(data)
    "#{package} #{json}"
  end
end
