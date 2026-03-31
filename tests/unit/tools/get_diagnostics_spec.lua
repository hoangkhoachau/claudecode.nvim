require("tests.busted_setup") -- Ensure test helpers are loaded

describe("Tool: get_diagnostics", function()
  local get_diagnostics_handler

  before_each(function()
    package.loaded["claudecode.tools.get_diagnostics"] = nil
    package.loaded["claudecode.logger"] = nil

    package.loaded["claudecode.logger"] = {
      debug = function() end,
      error = function() end,
      info = function() end,
      warn = function() end,
    }

    get_diagnostics_handler = require("claudecode.tools.get_diagnostics").handler

    _G.vim = _G.vim or {}
    _G.vim.lsp = _G.vim.lsp or {}
    _G.vim.diagnostic = _G.vim.diagnostic or {}
    _G.vim.api = _G.vim.api or {}
    _G.vim.fn = _G.vim.fn or {}

    _G.vim.diagnostic.get = spy.new(function()
      return {}
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
      return "/path/to/file_for_buf_" .. tostring(bufnr) .. ".lua"
    end)
    _G.vim.json.encode = spy.new(function(obj)
      -- Simple serialization for tests
      if type(obj) == "table" then
        return vim.inspect(obj)
      end
      return tostring(obj)
    end)
    _G.vim.fn.bufnr = spy.new(function(filepath)
      if filepath == "/test/file.lua" then
        return 1
      end
      return -1
    end)
    _G.vim.uri_to_fname = spy.new(function(uri)
      if uri:sub(1, 7) == "file://" then
        return uri:sub(8)
      end
      error("URI must contain a scheme: " .. uri)
    end)
    _G.vim.startswith = function(str, prefix)
      return str:sub(1, #prefix) == prefix
    end
  end)

  after_each(function()
    package.loaded["claudecode.tools.get_diagnostics"] = nil
    package.loaded["claudecode.logger"] = nil
    _G.vim.diagnostic.get = nil
    _G.vim.api.nvim_buf_get_name = nil
    _G.vim.json.encode = nil
    _G.vim.fn.bufnr = nil
    _G.vim.uri_to_fname = nil
    _G.vim.startswith = nil
  end)

  it("should return a single empty array text block when no diagnostics found", function()
    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    expect(result).to_be_table()
    expect(result.content).to_be_table()
    expect(#result.content).to_be(1)
    expect(result.content[1].type).to_be("text")
    assert.spy(_G.vim.diagnostic.get).was_called_with(nil)
    -- json.encode called once with empty array
    assert.spy(_G.vim.json.encode).was_called(1)
    local encoded_arg = _G.vim.json.encode.calls[1].vals[1]
    expect(type(encoded_arg)).to_be("table")
    expect(#encoded_arg).to_be(0)
  end)

  it("should group diagnostics by file URI", function()
    local mock_diagnostics = {
      { bufnr = 1, lnum = 10, col = 5, end_lnum = 10, end_col = 10, severity = 1, message = "Error message 1", source = "linter1" },
      { bufnr = 1, lnum = 20, col = 0, end_lnum = 20, end_col = 5, severity = 2, message = "Warning in same file", source = "linter1" },
      { bufnr = 2, lnum = 5, col = 3, end_lnum = 5, end_col = 8, severity = 3, message = "Info in file2", source = "linter2" },
    }
    _G.vim.diagnostic.get = spy.new(function()
      return mock_diagnostics
    end)

    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    expect(result.content).to_be_table()
    -- One text block containing the entire result
    expect(#result.content).to_be(1)
    expect(result.content[1].type).to_be("text")

    -- json.encode called once with DiagnosticFile[] array
    assert.spy(_G.vim.json.encode).was_called(1)
    local encoded_arg = _G.vim.json.encode.calls[1].vals[1]
    expect(type(encoded_arg)).to_be("table")
    -- Two files
    expect(#encoded_arg).to_be(2)

    -- First file has 2 diagnostics
    expect(encoded_arg[1].uri).to_be("file:///path/to/file_for_buf_1.lua")
    expect(#encoded_arg[1].diagnostics).to_be(2)

    -- Check first diagnostic structure
    local d1 = encoded_arg[1].diagnostics[1]
    expect(d1.message).to_be("Error message 1")
    expect(d1.severity).to_be("Error")
    expect(d1.range.start.line).to_be(10)
    expect(d1.range.start.character).to_be(5)
    expect(d1.range["end"].line).to_be(10)
    expect(d1.range["end"].character).to_be(10)
    expect(d1.source).to_be("linter1")

    -- Second diagnostic
    local d2 = encoded_arg[1].diagnostics[2]
    expect(d2.severity).to_be("Warning")

    -- Second file has 1 diagnostic
    expect(encoded_arg[2].uri).to_be("file:///path/to/file_for_buf_2.lua")
    expect(#encoded_arg[2].diagnostics).to_be(1)
    expect(encoded_arg[2].diagnostics[1].severity).to_be("Info")
  end)

  it("should map all severity levels to strings", function()
    local mock_diagnostics = {
      { bufnr = 1, lnum = 0, col = 0, severity = 1, message = "error", source = "s" },
      { bufnr = 1, lnum = 1, col = 0, severity = 2, message = "warning", source = "s" },
      { bufnr = 1, lnum = 2, col = 0, severity = 3, message = "info", source = "s" },
      { bufnr = 1, lnum = 3, col = 0, severity = 4, message = "hint", source = "s" },
    }
    _G.vim.diagnostic.get = spy.new(function()
      return mock_diagnostics
    end)

    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    local encoded_arg = _G.vim.json.encode.calls[1].vals[1]
    local diags = encoded_arg[1].diagnostics
    expect(diags[1].severity).to_be("Error")
    expect(diags[2].severity).to_be("Warning")
    expect(diags[3].severity).to_be("Info")
    expect(diags[4].severity).to_be("Hint")
  end)

  it("should filter out diagnostics with no file path", function()
    local mock_diagnostics = {
      { bufnr = 1, lnum = 10, col = 5, severity = 1, message = "Error message 1", source = "linter1" },
      { bufnr = 99, lnum = 20, col = 15, severity = 2, message = "Warning message 2", source = "linter2" },
    }
    _G.vim.diagnostic.get = spy.new(function()
      return mock_diagnostics
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
      if bufnr == 1 then
        return "/path/to/file1.lua"
      end
      return "" -- No path for bufnr 99
    end)

    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    local encoded_arg = _G.vim.json.encode.calls[1].vals[1]
    -- Only one file with a valid path
    expect(#encoded_arg).to_be(1)
    expect(encoded_arg[1].uri).to_be("file:///path/to/file1.lua")
    expect(#encoded_arg[1].diagnostics).to_be(1)
  end)

  it("should error if vim.diagnostic.get is not available", function()
    _G.vim.diagnostic.get = nil
    local success, err = pcall(get_diagnostics_handler, {})
    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32000)
    assert_contains(err.message, "Feature unavailable")
    assert_contains(err.data, "Diagnostics not available in this editor version/configuration.")
  end)

  it("should error if vim.diagnostic is not available", function()
    local old_diagnostic = _G.vim.diagnostic
    _G.vim.diagnostic = nil
    local success, err = pcall(get_diagnostics_handler, {})
    _G.vim.diagnostic = old_diagnostic

    expect(success).to_be_false()
    expect(err.code).to_be(-32000)
  end)

  it("should error if vim.lsp is not available", function()
    local old_lsp = _G.vim.lsp
    _G.vim.lsp = nil
    local success, err = pcall(get_diagnostics_handler, {})
    _G.vim.lsp = old_lsp

    expect(success).to_be_false()
    expect(err.code).to_be(-32000)
  end)

  it("should filter diagnostics by URI when provided", function()
    local mock_diagnostics = {
      { bufnr = 1, lnum = 10, col = 5, end_lnum = 10, end_col = 10, severity = 1, message = "Error in file1", source = "linter1" },
    }
    _G.vim.diagnostic.get = spy.new(function(bufnr)
      if bufnr == 1 then
        return mock_diagnostics
      end
      return {}
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
      if bufnr == 1 then
        return "/test/file.lua"
      end
      return ""
    end)

    local success, result = pcall(get_diagnostics_handler, { uri = "file:///test/file.lua" })
    expect(success).to_be_true()
    expect(#result.content).to_be(1)

    assert.spy(_G.vim.uri_to_fname).was_called_with("file:///test/file.lua")
    assert.spy(_G.vim.diagnostic.get).was_called_with(1)
    assert.spy(_G.vim.fn.bufnr).was_called_with("/test/file.lua")

    local encoded_arg = _G.vim.json.encode.calls[1].vals[1]
    expect(#encoded_arg).to_be(1)
    expect(encoded_arg[1].uri).to_be("file:///test/file.lua")
    expect(#encoded_arg[1].diagnostics).to_be(1)
    expect(encoded_arg[1].diagnostics[1].severity).to_be("Error")
  end)

  it("should error for URI of unopened file", function()
    _G.vim.fn.bufnr = spy.new(function()
      return -1
    end)

    local success, err = pcall(get_diagnostics_handler, { uri = "file:///unknown/file.lua" })
    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32001)
    expect(err.message).to_be("File not open")
    assert_contains(err.data, "File must be open to retrieve diagnostics: /unknown/file.lua")

    assert.spy(_G.vim.uri_to_fname).was_called_with("file:///unknown/file.lua")
    assert.spy(_G.vim.fn.bufnr).was_called_with("/unknown/file.lua")
    assert.spy(_G.vim.diagnostic.get).was_not_called()
  end)

  it("should include code field when diagnostic has a code", function()
    local mock_diagnostics = {
      { bufnr = 1, lnum = 0, col = 0, severity = 1, message = "err", source = "s", code = 42 },
    }
    _G.vim.diagnostic.get = spy.new(function()
      return mock_diagnostics
    end)

    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    local encoded_arg = _G.vim.json.encode.calls[1].vals[1]
    expect(encoded_arg[1].diagnostics[1].code).to_be("42")
  end)

  it("should use end_lnum/end_col for range end when available", function()
    local mock_diagnostics = {
      { bufnr = 1, lnum = 5, col = 2, end_lnum = 7, end_col = 8, severity = 1, message = "multi-line error" },
    }
    _G.vim.diagnostic.get = spy.new(function()
      return mock_diagnostics
    end)

    local success, result = pcall(get_diagnostics_handler, {})
    expect(success).to_be_true()
    local encoded_arg = _G.vim.json.encode.calls[1].vals[1]
    local d = encoded_arg[1].diagnostics[1]
    expect(d.range.start.line).to_be(5)
    expect(d.range.start.character).to_be(2)
    expect(d.range["end"].line).to_be(7)
    expect(d.range["end"].character).to_be(8)
  end)
end)
