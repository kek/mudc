# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mudc is an Elixir OTP application (v0.1.0) running on Elixir ~> 1.19. It's structured as a supervised application with `Mudc.Application` as the entry point.

## Common Commands

### Development
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `iex -S mix` - Start interactive shell with the application loaded

### Testing
- `mix test` - Run all tests
- `mix test test/mudc_test.exs` - Run a specific test file
- `mix test test/mudc_test.exs:5` - Run a specific test at line 5

### Code Quality
- `mix format` - Format code according to `.formatter.exs`
- `mix format --check-formatted` - Check if code is formatted

## Architecture

### Application Structure
The application follows standard OTP principles:
- `Mudc.Application` (lib/mudc/application.ex) - OTP application callback module that starts the supervision tree
- `Mudc.Supervisor` - Supervises child processes with `:one_for_one` strategy
- The supervisor's children list is currently empty and ready for workers to be added

### Module Organization
- `lib/mudc.ex` - Main module and public API
- `lib/mudc/` - Internal modules and implementation details
- `test/` - Test files mirroring the lib/ structure

### Testing
- Uses ExUnit as the test framework
- Doctests are enabled (see `doctest Mudc` in test files)
- Test helper is minimal, just starting ExUnit
