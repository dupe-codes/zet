-- Note-type (bin) resolver.
--
-- Every vault understands the two built-in note types (`draft`, `codex`). A
-- vault may additionally declare custom note types in
-- `<vault>/meta/configs/zet-bins.yaml`; a custom entry whose `tag` matches a
-- built-in overrides it.
--
-- A note-type maps a human-facing `tag` to the `bin` directory the note is
-- written into and the `template` it is rendered from, both relative to the
-- vault root.

local yaml = require "yaml"

local file_utils = require "src.file-utils"

local M = {}

local DEFAULTS = {
    {
        tag = "draft",
        bin = "chassis/knowledge/inbox",
        template = "meta/templates/draft.md",
    },
    {
        tag = "codex",
        bin = "chassis/knowledge/codex",
        template = "meta/templates/codex.md",
    },
}

local function file_exists(path)
    local fh = io.open(path, "r")
    if fh then
        fh:close()
        return true
    end
    return false
end

--- Resolve the note types available for a given vault.
-- @param vault_path absolute path to the vault root
-- @return ordered list of `{tag=string, bin=string, template=string}`
function M.resolve(vault_path)
    assert(
        type(vault_path) == "string" and vault_path ~= "",
        "bins.resolve requires a vault path"
    )

    -- Start from the built-in defaults, tracking position by tag so custom
    -- entries can override in place rather than appending a duplicate.
    local resolved = {}
    local index_by_tag = {}
    for _, row in ipairs(DEFAULTS) do
        resolved[#resolved + 1] =
            { tag = row.tag, bin = row.bin, template = row.template }
        index_by_tag[row.tag] = #resolved
    end

    local config_path = vault_path .. "/meta/configs/zet-bins.yaml"
    if file_exists(config_path) then
        local parsed = yaml.eval(file_utils.read_file(config_path))
        assert(
            type(parsed) == "table",
            "Malformed " .. config_path .. ": expected a mapping"
        )
        for _, row in ipairs(parsed.bins or {}) do
            assert(
                type(row.tag) == "string" and row.tag ~= "",
                config_path .. ": every bin needs a 'tag'"
            )
            assert(
                type(row.bin) == "string" and row.bin ~= "",
                config_path .. ": bin '" .. row.tag .. "' needs a 'bin'"
            )
            assert(
                type(row.template) == "string" and row.template ~= "",
                config_path .. ": bin '" .. row.tag .. "' needs a 'template'"
            )
            local entry =
                { tag = row.tag, bin = row.bin, template = row.template }
            local existing = index_by_tag[row.tag]
            if existing then
                resolved[existing] = entry
            else
                resolved[#resolved + 1] = entry
                index_by_tag[row.tag] = #resolved
            end
        end
    end

    return resolved
end

return M
