--- Tool implementation for getting diagnostics.
local schema = {
  description = "Get language diagnostics (errors, warnings) from the editor",
  inputSchema = {
    type = "object",
    properties = {
      uri = {
        type = "string",
        description = "Optional file URI to get diagnostics for. If not provided, gets diagnostics for all open files.",
      },
    },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

local SEVERITY_MAP = {
  [1] = "Error",
  [2] = "Warning",
  [3] = "Info",
  [4] = "Hint",
}

---Formats a list of raw Neovim diagnostics into a DiagnosticFile[] array
---grouped by file URI, matching the VS Code extension output format.
---@param diagnostics table Raw diagnostics from vim.diagnostic.get()
---@return table DiagnosticFile[] array
local function format_diagnostics(diagnostics)
  local files_map = {}
  local files_order = {}

  for _, diagnostic in ipairs(diagnostics) do
    local file_path = vim.api.nvim_buf_get_name(diagnostic.bufnr)
    if file_path and file_path ~= "" then
      local uri = "file://" .. file_path
      if not files_map[uri] then
        files_map[uri] = { uri = uri, diagnostics = {} }
        table.insert(files_order, uri)
      end
      table.insert(files_map[uri].diagnostics, {
        message = diagnostic.message,
        severity = SEVERITY_MAP[diagnostic.severity] or "Error",
        range = {
          start = {
            line = diagnostic.lnum,
            character = diagnostic.col,
          },
          ["end"] = {
            line = diagnostic.end_lnum or diagnostic.lnum,
            character = diagnostic.end_col or diagnostic.col,
          },
        },
        source = diagnostic.source or nil,
        code = diagnostic.code and tostring(diagnostic.code) or nil,
      })
    end
  end

  local result = {}
  for _, uri in ipairs(files_order) do
    table.insert(result, files_map[uri])
  end
  return result
end

---Handles the getDiagnostics tool invocation.
---Retrieves diagnostics from Neovim's diagnostic system.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with DiagnosticFile[] data
local function handler(params)
  if not vim.lsp or not vim.diagnostic or not vim.diagnostic.get then
    error({
      code = -32000,
      message = "Feature unavailable",
      data = "Diagnostics not available in this editor version/configuration.",
    })
  end

  local logger = require("claudecode.logger")
  logger.debug("getDiagnostics handler called with params: " .. vim.inspect(params))

  local raw_diagnostics

  if not params.uri then
    logger.debug("Getting diagnostics for all open buffers")
    raw_diagnostics = vim.diagnostic.get(nil)
  else
    local uri = params.uri
    local filepath = vim.startswith(uri, "file://") and vim.uri_to_fname(uri) or uri

    local bufnr = vim.fn.bufnr(filepath)
    if bufnr == -1 then
      logger.debug("File buffer must be open to get diagnostics: " .. filepath)
      error({
        code = -32001,
        message = "File not open",
        data = "File must be open to retrieve diagnostics: " .. filepath,
      })
    end

    logger.debug("Getting diagnostics for bufnr: " .. bufnr)
    raw_diagnostics = vim.diagnostic.get(bufnr)
  end

  local diagnostic_files = format_diagnostics(raw_diagnostics)

  return {
    content = {
      { type = "text", text = vim.json.encode(diagnostic_files) },
    },
  }
end

return {
  name = "getDiagnostics",
  schema = schema,
  handler = handler,
}
