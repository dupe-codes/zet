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

-- Diagnostic sink for non-fatal template anomalies — unexpected template
-- shapes that would otherwise drop the user's metadata silently. Routed
-- through a single overridable function so the "never silently ignore" rule
-- holds in production (writes to stderr) while tests can capture warnings.
function M.warn(message)
    assert(type(message) == "string", "note_writer.warn requires a string")
    io.stderr:write("[note_writer] " .. message .. "\n")
end

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
        local key_indent, trailing = line:match "^(%s*)tags:(.*)$"
        if key_indent and not handled then
            handled = true
            out[#out + 1] = line
            if trim(trailing) ~= "" then
                -- Inline form (`tags: [a, b]` or a scalar). The line-oriented
                -- merge only understands block lists, so splicing the user's
                -- tags in could yield malformed YAML. Preserve the template
                -- line and warn rather than silently drop the input.
                i = i + 1
                if #user_tags > 0 then
                    M.warn(
                        "template uses an inline 'tags:' list; "
                            .. #user_tags
                            .. " user tag(s) were not merged"
                    )
                end
            else
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
            end
        else
            out[#out + 1] = line
            i = i + 1
        end
    end
    return out, handled
end

-- Characters that force quoting when they LEAD a YAML plain scalar: each
-- would otherwise be read as a flow indicator, anchor, alias, tag, comment,
-- block-scalar header, or document marker rather than literal text.
local YAML_LEADING_INDICATORS = {}
for ch in ("-?:,[]{}#&*!|>'\"%@`"):gmatch "." do
    YAML_LEADING_INDICATORS[ch] = true
end

-- Decide whether `value` is safe to emit as a YAML plain (unquoted) scalar on
-- a `key: value` line. A plain scalar may not be empty, lead with an indicator
-- character, contain ": " or " #" (which would open a nested mapping or an
-- inline comment), end in a colon, or carry surrounding whitespace.
local function plain_scalar_is_safe(value)
    if value == "" then
        return false
    end
    if YAML_LEADING_INDICATORS[value:sub(1, 1)] then
        return false
    end
    if value:find(": ", 1, true) then
        return false
    end
    if value:find(" #", 1, true) then
        return false
    end
    if value:sub(-1) == ":" then
        return false
    end
    if value:match "^%s" then
        return false
    end
    if value:match "%s$" then
        return false
    end
    return true
end

-- Render `value` as a YAML scalar safe to place after a `key: `. Safe values
-- pass through unquoted to keep the frontmatter readable; anything else is
-- emitted as a double-quoted scalar with `\` and `"` escaped, which can carry
-- arbitrary text (colons, hashes, quotes) without corrupting the frontmatter.
local function yaml_scalar(value)
    assert(type(value) == "string", "yaml_scalar requires a string")
    if plain_scalar_is_safe(value) then
        return value
    end
    local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. escaped .. '"'
end

-- Set the `description:` value when the user supplied one. Modifies the
-- existing key in place; appends the key if the template lacks it. The value
-- is always rendered through `yaml_scalar` so a description containing a colon
-- (e.g. "Refactor: domain integration") cannot break the frontmatter.
local function set_description(lines, description)
    if description == "" then
        return lines
    end
    for idx, line in ipairs(lines) do
        local indent = line:match "^(%s*)description:"
        if indent then
            lines[idx] = indent .. "description: " .. yaml_scalar(description)
            return lines
        end
    end
    lines[#lines + 1] = "description: " .. yaml_scalar(description)
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

    -- Templates without frontmatter: there is nowhere to merge metadata into,
    -- so append the content to the template body verbatim. Warn rather than
    -- silently discard a description or tags the user took the time to enter.
    if not frontmatter then
        if description ~= "" or #user_tags > 0 then
            M.warn(
                "template has no '---' frontmatter; "
                    .. "description and tags were not written"
            )
        end
        return fill_dates(body .. content)
    end

    local lines, tags_handled = merge_tags(split_lines(frontmatter), user_tags)
    -- Template carried no `tags:` key: append a block list so the user's tags
    -- survive instead of vanishing (mirrors set_description appending its key).
    if not tags_handled and #user_tags > 0 then
        lines[#lines + 1] = "tags:"
        local seen = {}
        for _, tag in ipairs(user_tags) do
            if tag ~= "" and not seen[tag] then
                seen[tag] = true
                lines[#lines + 1] = "  - " .. tag
            end
        end
    end
    lines = set_description(lines, description)

    -- Fill dates over the WHOLE rendered document, not just the frontmatter, so
    -- a {{date}} placeholder in the body or appended content is honoured too.
    local rendered =
        "---\n" .. table.concat(lines, "\n") .. "\n---\n\n" .. body .. content
    return fill_dates(rendered)
end

return M
