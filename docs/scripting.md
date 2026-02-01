# Lua Scripting Guide

Mudc uses Lua for scripting via the Luerl library. Scripts can define triggers, aliases, and other automation to enhance your MUD experience.

## Quick Start

1. Create a scripts directory:
   ```bash
   mkdir -p ~/.config/mudc/scripts
   ```

2. Create a script file (e.g., `~/.config/mudc/scripts/01-triggers.lua`):
   ```lua
   -- Auto-flee when health is low
   mud.trigger("You are feeling very weak", function()
     mud.send("flee")
     mud.echo("Auto-fleeing!")
   end)
   ```

3. Scripts are loaded automatically on startup and when changed.

## Script Loading

Scripts are loaded from the directory specified in `config.lua`:

```lua
return {
  scripting = {
    script_dirs = {"~/.config/mudc/scripts"},
    auto_reload = true
  }
}
```

Scripts load in alphabetical order. Use numeric prefixes to control order:

```
~/.config/mudc/scripts/
  01-core.lua       # Loaded first
  02-triggers.lua   # Loaded second
  03-aliases.lua    # Loaded third
  99-custom.lua     # Loaded last
```

## The `mud` API

### mud.send(command)

Send a command to the MUD server.

```lua
mud.send("look")
mud.send("say Hello, world!")
mud.send("cast 'cure light' self")
```

### mud.echo(text)

Display text locally in the game window. Does not send to server.

```lua
mud.echo("This is a local message")
mud.echo("HP: " .. current_hp .. "/" .. max_hp)
```

Output appears prefixed with `[Lua]`.

### mud.trigger(pattern, callback)

Register a trigger that fires when text from the server matches the pattern.

**Parameters:**
- `pattern` - String to match in game text (substring match)
- `callback` - Function to call when pattern matches. Receives the full line as argument.

**Examples:**

```lua
-- Simple trigger
mud.trigger("You are hungry", function()
  mud.send("eat bread")
end)

-- Trigger with the matched line
mud.trigger("tells you", function(line)
  mud.echo("Got a tell: " .. line)
end)

-- Auto-loot
mud.trigger("is DEAD", function()
  mud.send("get all corpse")
end)

-- Track kills
local kill_count = 0
mud.trigger("You receive", function(line)
  if string.find(line, "experience") then
    kill_count = kill_count + 1
    mud.echo("Kills this session: " .. kill_count)
  end
end)
```

**Notes:**
- Pattern matching is substring-based (not regex)
- Triggers fire for each matching line
- Triggers also match against prompts
- Multiple triggers can match the same text

### mud.alias(name, callback)

Register an alias that expands when typed as a command.

**Parameters:**
- `name` - The alias command name (first word)
- `callback` - Function to call. Receives remaining arguments as a string.

**Examples:**

```lua
-- Simple alias
mud.alias("h", function()
  mud.send("help")
end)

-- Alias with arguments
mud.alias("tt", function(target)
  mud.send("cast 'cure light' " .. target)
end)
-- Usage: tt self  ->  cast 'cure light' self

-- Complex alias
mud.alias("buff", function()
  mud.send("cast 'armor'")
  mud.send("cast 'bless'")
  mud.send("cast 'shield'")
end)

-- Alias that parses arguments
mud.alias("give", function(args)
  local item, target = string.match(args, "(%S+)%s+(%S+)")
  if item and target then
    mud.send("get " .. item .. " bag")
    mud.send("give " .. item .. " " .. target)
  else
    mud.echo("Usage: give <item> <target>")
  end
end)
```

### mud.gag()

Suppress the current line from being displayed. Call this from within a trigger callback.

```lua
-- Hide spam messages
mud.trigger("The sun rises", function()
  mud.gag()
end)

-- Hide but log
mud.trigger("You feel hungry", function()
  mud.gag()
  -- Line is hidden but trigger still fired
end)
```

### print(...)

The standard Lua `print()` function is redirected to `mud.echo()`.

```lua
print("Debug:", some_variable)  -- Same as mud.echo()
```

## The `game` API

### game.vitals()

Get current character vitals from GMCP data.

```lua
local v = game.vitals()
print("HP:", v.hp, "/", v.max_hp)
print("Mana:", v.mana, "/", v.max_mana)
print("Moves:", v.moves, "/", v.max_moves)
```

Returns a table with fields populated by GMCP (fields depend on MUD support).

### game.room()

Get current room information from GMCP data.

```lua
local r = game.room()
print("Room:", r.name)
print("Area:", r.area)
print("Exits:", table.concat(r.exits or {}, ", "))
```

Returns a table with fields populated by GMCP (fields depend on MUD support).

## Common Patterns

### Auto-Attack

```lua
local auto_attack = false
local target = nil

mud.alias("aa", function(t)
  if t and t ~= "" then
    target = t
    auto_attack = true
    mud.echo("Auto-attacking: " .. target)
    mud.send("kill " .. target)
  else
    auto_attack = false
    mud.echo("Auto-attack disabled")
  end
end)

mud.trigger("is DEAD", function()
  if auto_attack and target then
    mud.send("kill " .. target)
  end
end)
```

### Speedwalking

```lua
mud.alias("go", function(path)
  for dir in string.gmatch(path, "%a") do
    local dirs = {
      n = "north", s = "south", e = "east", w = "west",
      u = "up", d = "down"
    }
    if dirs[dir] then
      mud.send(dirs[dir])
    end
  end
end)
-- Usage: go nneswu  ->  north, north, east, south, west, up
```

### Prompt Parsing

```lua
local hp, max_hp = 0, 0

mud.trigger(">", function(line)
  -- Parse prompt like: [100/100hp 50/50m 100/100mv]>
  local h, mh = string.match(line, "(%d+)/(%d+)hp")
  if h and mh then
    hp = tonumber(h)
    max_hp = tonumber(mh)
    
    -- Auto-heal at 50%
    if hp < max_hp * 0.5 then
      mud.send("cast 'cure light' self")
    end
  end
end)
```

### Session Statistics

```lua
local stats = {
  kills = 0,
  deaths = 0,
  xp_gained = 0
}

mud.trigger("is DEAD", function()
  stats.kills = stats.kills + 1
end)

mud.trigger("You have been KILLED", function()
  stats.deaths = stats.deaths + 1
end)

mud.trigger("You receive (%d+) experience", function(line)
  local xp = string.match(line, "(%d+) experience")
  if xp then
    stats.xp_gained = stats.xp_gained + tonumber(xp)
  end
end)

mud.alias("stats", function()
  mud.echo("=== Session Stats ===")
  mud.echo("Kills: " .. stats.kills)
  mud.echo("Deaths: " .. stats.deaths)
  mud.echo("XP Gained: " .. stats.xp_gained)
end)
```

### Conditional Commands

```lua
mud.alias("heal", function(target)
  local v = game.vitals()
  
  if v.mana < 20 then
    mud.echo("Not enough mana!")
    return
  end
  
  if target == "" then
    target = "self"
  end
  
  if v.hp < v.max_hp * 0.3 then
    mud.send("cast 'cure critical' " .. target)
  elseif v.hp < v.max_hp * 0.7 then
    mud.send("cast 'cure serious' " .. target)
  else
    mud.send("cast 'cure light' " .. target)
  end
end)
```

## Script Organization

### Recommended Structure

```
~/.config/mudc/scripts/
  01-utils.lua      # Helper functions
  02-triggers.lua   # All triggers
  03-aliases.lua    # All aliases
  10-combat.lua     # Combat-specific scripts
  20-travel.lua     # Movement/navigation
  99-local.lua      # Machine-specific overrides
```

### Using Multiple Files

Scripts share the global Lua state, so functions defined in earlier scripts are available in later ones:

```lua
-- 01-utils.lua
function is_low_hp()
  local v = game.vitals()
  return v.hp < v.max_hp * 0.3
end

-- 02-triggers.lua
mud.trigger("attacks you", function()
  if is_low_hp() then
    mud.send("flee")
  end
end)
```

## Hot Reloading

Scripts are automatically reloaded when modified (if `auto_reload = true` in config). When scripts reload:

1. All triggers and aliases are cleared
2. Scripts are re-executed in order
3. Global Lua state is preserved

To manually clear and reload:

```elixir
# From remote REPL
Mudc.Scripting.Engine.reload()
```

## Debugging

### Echo Debug Messages

```lua
local DEBUG = true

function debug(msg)
  if DEBUG then
    mud.echo("[DEBUG] " .. msg)
  end
end

mud.trigger("some pattern", function(line)
  debug("Trigger fired: " .. line)
  -- ... rest of trigger
end)
```

### Check Registered Triggers/Aliases

From the remote REPL:

```elixir
# List all triggers
Mudc.Scripting.TriggerManager.list()

# List all aliases
Mudc.Scripting.AliasManager.list()
```

## Limitations

- Pattern matching is substring-based, not regex (use Lua's `string.match` inside callbacks for regex)
- No persistent storage between restarts (use external files if needed)
- GMCP data availability depends on MUD server support
- Triggers fire on partial line matches; be specific with patterns to avoid false positives

## See Also

- [Configuration Guide](./configuration.md) - Config file format
- [Remote REPL](./remote-repl.md) - Debug running instance
- [Event Bus](./event-bus.md) - Internal event system
