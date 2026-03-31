---@brief [[
--- Manages configuration for the Claude Code Neovim integration.
--- Provides default settings, validation, and application of user-defined configurations.
---@brief ]]
---@module 'claudecode.config'

local M = {}

---@type ClaudeCodeConfig
M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  log_level = "info",
  track_selection = true,
  focus_on_send = true, -- When true, focus the tmux pane running Claude after sending context
  visual_demotion_delay_ms = 50, -- Milliseconds to wait before demoting a visual selection
  connection_wait_delay = 600, -- Milliseconds to wait after connection before sending queued @ mentions
  connection_timeout = 10000, -- Maximum time to wait for Claude Code to connect (milliseconds)
  queue_timeout = 5000, -- Maximum time to keep @ mentions in queue (milliseconds)
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false, -- Open diff in a new tab (false = use current tab)
    keep_terminal_focus = false,
    hide_terminal_in_new_tab = false,
    on_new_file_reject = "keep_empty", -- "keep_empty" leaves an empty buffer; "close_window" closes the placeholder split
  },
}

---Validates the provided configuration table.
---Throws an error if any validation fails.
---@param config table The configuration table to validate.
---@return boolean true if the configuration is valid.
function M.validate(config)
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )

  assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")

  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid_log_level = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid_log_level = true
      break
    end
  end
  assert(is_valid_log_level, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

  assert(type(config.track_selection) == "boolean", "track_selection must be a boolean")
  if config.focus_on_send ~= nil then
    assert(type(config.focus_on_send) == "boolean", "focus_on_send must be a boolean")
  end

  assert(
    type(config.visual_demotion_delay_ms) == "number" and config.visual_demotion_delay_ms >= 0,
    "visual_demotion_delay_ms must be a non-negative number"
  )

  assert(
    type(config.connection_wait_delay) == "number" and config.connection_wait_delay >= 0,
    "connection_wait_delay must be a non-negative number"
  )

  assert(
    type(config.connection_timeout) == "number" and config.connection_timeout > 0,
    "connection_timeout must be a positive number"
  )

  assert(type(config.queue_timeout) == "number" and config.queue_timeout > 0, "queue_timeout must be a positive number")

  assert(type(config.diff_opts) == "table", "diff_opts must be a table")
  if config.diff_opts.layout ~= nil then
    assert(
      config.diff_opts.layout == "vertical" or config.diff_opts.layout == "horizontal",
      "diff_opts.layout must be 'vertical' or 'horizontal'"
    )
  end
  if config.diff_opts.open_in_new_tab ~= nil then
    assert(type(config.diff_opts.open_in_new_tab) == "boolean", "diff_opts.open_in_new_tab must be a boolean")
  end
  if config.diff_opts.keep_terminal_focus ~= nil then
    assert(type(config.diff_opts.keep_terminal_focus) == "boolean", "diff_opts.keep_terminal_focus must be a boolean")
  end
  if config.diff_opts.hide_terminal_in_new_tab ~= nil then
    assert(
      type(config.diff_opts.hide_terminal_in_new_tab) == "boolean",
      "diff_opts.hide_terminal_in_new_tab must be a boolean"
    )
  end
  if config.diff_opts.on_new_file_reject ~= nil then
    assert(
      type(config.diff_opts.on_new_file_reject) == "string"
        and (
          config.diff_opts.on_new_file_reject == "keep_empty" or config.diff_opts.on_new_file_reject == "close_window"
        ),
      "diff_opts.on_new_file_reject must be 'keep_empty' or 'close_window'"
    )
  end

  -- Legacy diff options (accept if present to avoid breaking old configs)
  if config.diff_opts.auto_close_on_accept ~= nil then
    assert(type(config.diff_opts.auto_close_on_accept) == "boolean", "diff_opts.auto_close_on_accept must be a boolean")
  end
  if config.diff_opts.show_diff_stats ~= nil then
    assert(type(config.diff_opts.show_diff_stats) == "boolean", "diff_opts.show_diff_stats must be a boolean")
  end
  if config.diff_opts.vertical_split ~= nil then
    assert(type(config.diff_opts.vertical_split) == "boolean", "diff_opts.vertical_split must be a boolean")
  end
  if config.diff_opts.open_in_current_tab ~= nil then
    assert(type(config.diff_opts.open_in_current_tab) == "boolean", "diff_opts.open_in_current_tab must be a boolean")
  end

  return true
end

---Applies user configuration on top of default settings and validates the result.
---@param user_config table|nil The user-provided configuration table.
---@return ClaudeCodeConfig config The final, validated configuration table.
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  if user_config then
    -- Use vim.tbl_deep_extend if available, otherwise simple merge
    if vim.tbl_deep_extend then
      config = vim.tbl_deep_extend("force", config, user_config)
    else
      -- Simple fallback for testing environment
      for k, v in pairs(user_config) do
        config[k] = v
      end
    end
  end

  -- Backward compatibility: map legacy diff options to new fields if provided
  if config.diff_opts then
    local d = config.diff_opts
    -- Map vertical_split -> layout (legacy option takes precedence)
    if type(d.vertical_split) == "boolean" then
      d.layout = d.vertical_split and "vertical" or "horizontal"
    end
    -- Map open_in_current_tab -> open_in_new_tab (legacy option takes precedence)
    if type(d.open_in_current_tab) == "boolean" then
      d.open_in_new_tab = not d.open_in_current_tab
    end
  end

  M.validate(config)

  return config
end

return M
