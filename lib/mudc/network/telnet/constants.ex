defmodule Mudc.Network.Telnet.Constants do
  @moduledoc """
  Telnet protocol byte constants.

  Reference: RFC 854 (Telnet), RFC 855 (Telnet Options)
  """

  # Telnet commands
  # Interpret As Command
  @iac 255
  @dont 254
  @telnet_do 253
  @wont 252
  @will 251
  # Subnegotiation Begin
  @sb 250
  # Go Ahead
  @ga 249
  # Erase Line
  @el 248
  # Erase Character
  @ec 247
  # Are You There
  @ayt 246
  # Abort Output
  @ao 245
  # Interrupt Process
  @ip 244
  # Break
  @brk 243
  # Data Mark
  @dm 242
  # No Operation
  @nop 241
  # Subnegotiation End
  @se 240

  # Telnet options
  @opt_echo 1
  @opt_suppress_go_ahead 3
  @opt_status 5
  @opt_timing_mark 6
  @opt_terminal_type 24
  # NAWS
  @opt_window_size 31
  @opt_terminal_speed 32
  @opt_remote_flow 33
  @opt_linemode 34
  @opt_environ 36
  @opt_new_environ 39
  @opt_charset 42
  # MUD Server Data Protocol
  @opt_msdp 69
  # MUD Server Status Protocol
  @opt_mssp 70
  # MCCP1
  @opt_compress 85
  # MCCP2
  @opt_compress2 86
  # MUD Sound Protocol
  @opt_msp 90
  # MUD eXtension Protocol
  @opt_mxp 91
  # Zenith MUD Protocol
  @opt_zmp 93
  # Achaea Telnet Client Protocol
  @opt_atcp 200
  # Generic MUD Communication Protocol
  @opt_gmcp 201

  # Export all constants as functions for easy access
  def iac, do: @iac
  def dont, do: @dont
  def do_, do: @telnet_do
  def wont, do: @wont
  def will, do: @will
  def sb, do: @sb
  def se, do: @se
  def ga, do: @ga
  def el, do: @el
  def ec, do: @ec
  def ayt, do: @ayt
  def ao, do: @ao
  def ip, do: @ip
  def brk, do: @brk
  def dm, do: @dm
  def nop, do: @nop

  # Options
  def opt_echo, do: @opt_echo
  def opt_suppress_go_ahead, do: @opt_suppress_go_ahead
  def opt_terminal_type, do: @opt_terminal_type
  def opt_window_size, do: @opt_window_size
  def opt_gmcp, do: @opt_gmcp
  def opt_msdp, do: @opt_msdp
  def opt_mssp, do: @opt_mssp
  def opt_compress2, do: @opt_compress2
  def opt_mxp, do: @opt_mxp

  @doc """
  Returns the name of a Telnet command byte.
  """
  def command_name(byte) do
    case byte do
      @iac -> "IAC"
      @dont -> "DONT"
      @telnet_do -> "DO"
      @wont -> "WONT"
      @will -> "WILL"
      @sb -> "SB"
      @se -> "SE"
      @ga -> "GA"
      @el -> "EL"
      @ec -> "EC"
      @ayt -> "AYT"
      @ao -> "AO"
      @ip -> "IP"
      @brk -> "BRK"
      @dm -> "DM"
      @nop -> "NOP"
      _ -> "UNKNOWN(#{byte})"
    end
  end

  @doc """
  Returns the name of a Telnet option byte.
  """
  def option_name(byte) do
    case byte do
      @opt_echo -> "ECHO"
      @opt_suppress_go_ahead -> "SUPPRESS-GO-AHEAD"
      @opt_status -> "STATUS"
      @opt_timing_mark -> "TIMING-MARK"
      @opt_terminal_type -> "TERMINAL-TYPE"
      @opt_window_size -> "NAWS"
      @opt_terminal_speed -> "TERMINAL-SPEED"
      @opt_remote_flow -> "REMOTE-FLOW"
      @opt_linemode -> "LINEMODE"
      @opt_environ -> "ENVIRON"
      @opt_new_environ -> "NEW-ENVIRON"
      @opt_charset -> "CHARSET"
      @opt_msdp -> "MSDP"
      @opt_mssp -> "MSSP"
      @opt_compress -> "COMPRESS"
      @opt_compress2 -> "COMPRESS2"
      @opt_msp -> "MSP"
      @opt_mxp -> "MXP"
      @opt_zmp -> "ZMP"
      @opt_atcp -> "ATCP"
      @opt_gmcp -> "GMCP"
      _ -> "OPT(#{byte})"
    end
  end
end
