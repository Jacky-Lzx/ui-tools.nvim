local M = {}

-- Explicit, optional adapter. Never loads git-tools or computes a diff itself.
function M.setup()
  return require("ui_tools.scrollbar").register("git_tools", function(ctx)
    local buffer = package.loaded["git_tools.buffer"]
    if not buffer then
      return {}
    end
    local marks = {}
    for _, hunk in ipairs(buffer.get_hunks(ctx.buf)) do
      local kind = hunk.old_count == 0 and "Add" or hunk.new_count == 0 and "Delete" or "Change"
      local first = math.max(1, hunk.new_start)
      marks[#marks + 1] = {
        line = first,
        end_line = math.max(first, hunk.new_start + hunk.new_count - 1),
        hl = "GitTools" .. kind,
        char = kind == "Delete" and "_" or "┃",
        priority = 60,
      }
    end
    return marks
  end)
end

return M
