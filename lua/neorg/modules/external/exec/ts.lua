

local M = {
  ts = nil,
}

local title = "external.exec"

M.current_code_block = function()
  local ts = M.ts.get_ts_utils()
  local node = ts.get_node_at_cursor(0, true)
  local p = M.ts.find_parent(node, "^ranged_verbatim_tag$")
  return p
end

M.find_next_sibling = function(node, types)
  local _node = node:next_sibling()

  while _node do
    if type(types) == "string" then
      if _node:type():match(types) then
        return _node
      end
    elseif vim.tbl_contains(types, _node:type()) then
      return _node
    end

    _node = _node:next_sibling()
  end
end

M.find_all_code_blocks = function()
  local buffer = 0
  local document_root = M.ts.get_document_root(buffer)
  return M.find_code_blocks_for_node(buffer, document_root)
end

M.contained_code_blocks = function()
  local buffer = 0
  -- local ts = module.required["core.integrations.treesitter"].get_ts_utils()
  -- local node = ts.get_node_at_cursor(buffer, true)

  local lineNum = vim.api.nvim_win_get_cursor(0)[1]
  local node = M.ts.get_first_node_on_line(buffer, lineNum-1, {})
  -- vim.notify(string.format("%s", node))

  return M.find_code_blocks_for_node(buffer, node)
end

M.find_code_blocks_for_node = function(buffer, root)
  local parsed_document_metadata = M.ts.get_document_metadata(buffer)

  if vim.tbl_isempty(parsed_document_metadata) or not parsed_document_metadata.tangle then
    parsed_document_metadata = {
      exec = {},
    }
  end


  local options = {
    languages = {},
    scope = parsed_document_metadata.exec.scope or "all", -- "all" | "tagged" | "main"
  }


  local query_str = neorg.lib.match(options.scope)({
    _ = [[
    (ranged_verbatim_tag
    name: (tag_name) @_name
    (#eq? @_name "code")
    (tag_parameters
    .
    (tag_param) @_language)) @tag
    ]],
    tagged = [[
    (ranged_verbatim_tag
    [(strong_carryover_set
    (strong_carryover
    name: (tag_name) @_strong_carryover_tag_name
    (#eq? @_strong_carryover_tag_name "exec.name")))
    (weak_carryover_set
    (weak_carryover
    name: (tag_name) @_weak_carryover_tag_name
    (#eq? @_weak_carryover_tag_name "exec.name")))]
    name: (tag_name) @_name
    (#eq? @_name "code")
    (tag_parameters
    .
    (tag_param) @_language)) @tag
    ]],
  })


  local query = neorg.utils.ts_parse_query("norg", query_str)
  local nodes = {}

  for id, node in query:iter_captures(root, buffer, 0, -1) do
    -- vim.notify('found 1')
    local capture = query.captures[id]
    if capture == "tag" then
      table.insert(nodes, node)
    end
  end
  return nodes

end

M.node_info = function(p)
  -- TODO: Add checks here
  local cb = M.ts.get_tag_info(p, true)
  if not cb then
    vim.notify("Not inside a tag!", "warn", {title = title})
    return
  end
  return cb
end

M.node_carryover_tags = function(p)
  local tags = {}
  for child, _ in p:iter_children() do
    if child:type() == "strong_carryover_set" then
      for child2, _ in child:iter_children() do
        if child2:type() == "strong_carryover" then
          local cot = M.ts.get_tag_info(child2, true)
          tags[cot.name] = cot.parameters
          -- vim.notify(string.format("%s: %s", cot.name, table.concat(cot.parameters, '-')))
        end
      end
    end
  end
  return tags
end


return M
