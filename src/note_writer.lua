-- Note renderer.
--
-- Renders a finished note by merging user input into a vault's own template.
-- Templates carry a YAML frontmatter block delimited by `---` lines, e.g.
--
--     ---
--     type: draft
--     description:
--     tags:
--       - inbox
--     created_at: {{date:YYYY-MM-DD}}
--     ---
--
-- We deliberately transform the frontmatter line-by-line rather than doing a
-- parse -> mutate -> re-serialize round-trip with the bundled `lua-yaml`. That
-- library mis-parses the real chassis templates: an empty value (`description:`)
-- swallows the following key into a nested table, and a bare date scalar is
-- coerced to an integer timestamp. A line-oriented transform sidesteps both
-- bugs and preserves the template's formatting exactly.

local file_utils = require "src.file-utils"

local M = {}

-- Convert a moment.js-style date format to an `os.date`/strftime format.
local MOMENT_TO_STRFTIME = {
    { "YYYY", "%%Y" },
    { "MM", "%%m" },
    { "DD", "%%d" },
    { "HH", "%%H" },
    { "mm", "%%M" },
    { "ss", "%%S" },
}

local function moment_to_strftime(fmt)
    local out = fmt
    for _, pair in ipairs(MOMENT_TO_STRFTIME) do
        out = out:gsub(pair[1], pair[2])
    end
    return out
end

-- Replace `{{date:FORMAT}}` and bare `{{date}}` placeholders with the current
-- date, formatted via the (converted) moment format.
local function fill_dates(text)
    text = text:gsub("{{date:(.-)}}", function(fmt)
        return os.date(moment_to_strftime(fmt))
    end)
    text = text:gsub("{{date}}", function()
        return os.date "%Y-%m-%d"
    end)
    return text
end

-- Trim leading/trailing whitespace.
local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split a template into its frontmatter body (the lines between the leading
-- `---` fences, without the fences) and everything after the closing fence.
-- Returns `nil` for the frontmatter when the template has no `---` block.
local function split_frontmatter(template)
    -- Leading fence must be the very first line.
    if not template:match "^%-%-%-\r?\n" then
        return nil, template
    end
    local fm, rest = template:match "^%-%-%-\r?\n(.-)\r?\n%-%-%-\r?\n?(.*)$"
    if not fm then
        return nil, template
    end
    return fm, rest
end

-- Rewrite the `tags:` block, appending the user's tags after the template's
-- own (e.g. `inbox`/`codex`), de-duplicated and order-preserving. Returns the
-- new list of frontmatter lines.
local function merge_tags(lines, user_tags)
    local out = {}
    local i = 1
    local handled = false
    while i <= #lines do
        local line = lines[i]
        local key_indent = line:match "^(%s*)tags:%s*$"
        if key_indent and not handled then
            handled = true
            out[#out + 1] = line
            -- Collect the template's existing list items and their indent.
            local existing, item_indent = {}, nil
            i = i + 1
            while i <= #lines do
                local indent, value = lines[i]:match "^(%s*)%-%s+(.+)$"
                if not indent then
                    break
                end
                item_indent = item_indent or indent
                existing[#existing + 1] = trim(value)
                i = i + 1
            end
            item_indent = item_indent or (key_indent .. "  ")
            -- Merge existing + user tags, de-duplicated, order-preserving.
            local seen, merged = {}, {}
            for _, list in ipairs { existing, user_tags } do
                for _, tag in ipairs(list) do
                    if tag ~= "" and not seen[tag] then
                        seen[tag] = true
                        merged[#merged + 1] = tag
                    end
                end
            end
            for _, tag in ipairs(merged) do
                out[#out + 1] = item_indent .. "- " .. tag
            end
        else
            out[#out + 1] = line
            i = i + 1
        end
    end
    return out
end

-- Set the `description:` value when the user supplied one. Modifies the
-- existing key in place; appends the key if the template lacks it.
local function set_description(lines, description)
    if description == "" then
        return lines
    end
    for idx, line in ipairs(lines) do
        local indent = line:match "^(%s*)description:"
        if indent then
            lines[idx] = indent .. "description: " .. description
            return lines
        end
    end
    lines[#lines + 1] = "description: " .. description
    return lines
end

local function split_lines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch "(.-)\r?\n" do
        lines[#lines + 1] = line
    end
    -- Drop the trailing empty element produced by the sentinel newline.
    if lines[#lines] == "" then
        lines[#lines] = nil
    end
    return lines
end

--- Render a note from a template.
-- @param template_path absolute path to the template file
-- @param fields table with `description` (string), `tags` (list of strings)
--               and `content` (string)
-- @return the rendered note as a string
function M.render(template_path, fields)
    assert(
        type(template_path) == "string" and template_path ~= "",
        "note_writer.render requires a template path"
    )
    local template = file_utils.read_file(template_path)

    local description = trim(fields.description or "")
    local user_tags = fields.tags or {}
    local content = fields.content or ""

    local frontmatter, body = split_frontmatter(template)

    -- Templates without frontmatter: nothing to merge into, so just append the
    -- content to the template body verbatim.
    if not frontmatter then
        return body .. content
    end

    local lines = split_lines(frontmatter)
    lines = merge_tags(lines, user_tags)
    lines = set_description(lines, description)

    local rendered_fm = fill_dates(table.concat(lines, "\n"))
    return "---\n" .. rendered_fm .. "\n---\n\n" .. body .. content
end

return M
