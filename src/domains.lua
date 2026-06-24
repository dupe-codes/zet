-- Domain registry loader.
--
-- Reads the shared context-domain registry from `~/.claude/domains.json` and
-- expands it into an ordered list suitable for the domain dropdown. The file is
-- a JSON *object* keyed by domain name; we flatten it to a sorted list so the
-- dropdown order is deterministic across runs.

local json = require "dkjson"

local file_utils = require "src.file-utils"

local M = {}

local REGISTRY_PATH = os.getenv "HOME" .. "/.claude/domains.json"

-- Whether a registry path is rooted such that it resolves independently of the
-- current working directory: an absolute `/...` path, or a `~`/`~/...` path we
-- expand against $HOME. A relative path would resolve against the launching
-- CWD and is therefore rejected at the boundary (see M.load).
local function path_is_rooted(path)
    if path:sub(1, 1) == "/" then
        return true
    end
    if path == "~" then
        return true
    end
    if path:match "^~/" then
        return true
    end
    return false
end

-- Expand a leading `~` (and `~/`) against $HOME. Leaves any other path as-is.
local function expand_home(path)
    local home = os.getenv "HOME"
    if path == "~" then
        return home
    end
    local rest = path:match "^~/(.*)$"
    if rest then
        return home .. "/" .. rest
    end
    return path
end

--- Load and expand the registered context domains.
-- @return ordered list of `{name=string, path=string, description=string}`
function M.load()
    local raw = file_utils.read_file(REGISTRY_PATH)
    local parsed, _, err = json.decode(raw)
    assert(
        not err,
        "Failed to parse " .. REGISTRY_PATH .. ": " .. tostring(err)
    )
    assert(
        type(parsed) == "table",
        REGISTRY_PATH .. " did not parse to a JSON object"
    )

    -- Collect domain names so we can emit a deterministic, sorted order.
    local names = {}
    for name in pairs(parsed) do
        names[#names + 1] = name
    end
    table.sort(names)

    local domains = {}
    for _, name in ipairs(names) do
        local entry = parsed[name]
        assert(
            type(entry) == "table",
            "Domain '" .. name .. "' is not an object"
        )
        assert(
            type(entry.path) == "string" and entry.path ~= "",
            "Domain '" .. name .. "' is missing a 'path'"
        )
        assert(
            path_is_rooted(entry.path),
            "Domain '"
                .. name
                .. "' path must be absolute or ~-rooted, got: "
                .. entry.path
        )
        domains[#domains + 1] = {
            name = name,
            path = expand_home(entry.path),
            description = entry.description or "",
        }
    end

    assert(#domains > 0, "No domains found in " .. REGISTRY_PATH)
    return domains
end

return M
