---Tmux integration utilities for claudecode.nvim.
---Provides pane detection, focus, and window-scoped port advertisement.
---@module 'claudecode.tmux'

local M = {}

local WINDOW_PORT_VAR = "@claude_port"

---Check if we're running inside tmux.
---@return boolean
local function in_tmux()
  return os.getenv("TMUX") ~= nil
end

---Find the tmux pane running the claude process.
---@return string|nil pane_id The pane ID (e.g. "%3") or nil if not found
local function find_claude_pane()
  local output = vim.fn.system("tmux list-panes -a -F '#{pane_id} #{pane_current_command}' 2>/dev/null")
  if vim.v.shell_error ~= 0 or not output or output == "" then
    return nil
  end
  for line in output:gmatch("[^\n]+") do
    local pane_id, cmd = line:match("^(%S+)%s+(.+)$")
    if pane_id and cmd and cmd:match("^claude") then
      return pane_id
    end
  end
  return nil
end

---Get the port previously advertised on this tmux window, if any.
---@return number|nil port
function M.get_window_port()
  if not in_tmux() then
    return nil
  end
  local val = vim.fn.system("tmux show-options -wqv " .. WINDOW_PORT_VAR .. " 2>/dev/null")
  val = val:gsub("%s+$", "")
  return val ~= "" and tonumber(val) or nil
end

---Focus the tmux pane running Claude Code.
---Does nothing if not inside tmux or no Claude pane is found.
function M.focus_claude_pane()
  if not in_tmux() then
    return
  end
  local pane_id = find_claude_pane()
  if pane_id then
    vim.fn.system("tmux select-pane -t " .. pane_id)
  end
end

---Advertise the bridge port on the current tmux window.
---If a port is already set by another live Neovim instance, refuses to overwrite.
---If the old port's lock file is gone (crashed instance), overwrites it.
---@param port number The WebSocket port to advertise
---@return boolean success
---@return string|nil error
function M.advertise_port(port)
  if not in_tmux() then
    return true, nil
  end

  local existing = vim.fn.system("tmux show-options -wqv " .. WINDOW_PORT_VAR .. " 2>/dev/null")
  existing = existing:gsub("%s+$", "")

  if existing ~= "" and existing ~= tostring(port) then
    -- Check if the existing port's lock file still exists (stale if nvim crashed)
    local lock_dir = os.getenv("CLAUDE_CONFIG_DIR") or (os.getenv("HOME") .. "/.claude/ide")
    local lock_path = lock_dir .. "/" .. existing .. ".lock"
    if vim.fn.filereadable(lock_path) == 1 then
      return false, "Window already has a Neovim bridge on port " .. existing
    end
  end

  vim.fn.system("tmux set-option -w " .. WINDOW_PORT_VAR .. " " .. port)
  return true, nil
end

---Keep the port advertisement on exit — intentionally a no-op so the port
---persists across nvim restarts and is reused by the next session.
function M.unadvertise_port()
end

return M
