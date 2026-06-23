-- Tests for src/domains.lua.
--
-- Goal: verify the context-domain registry loader — deterministic sorted order
-- across runs, `~`/`~/` home expansion, the default empty description, and the
-- boundary assertions that reject a missing/unparseable/empty registry or a
-- malformed entry (including the newly-required absolute-or-~ path contract).
-- We assert the whole expanded list so ordering and expansion are checked
-- together, the way the dropdown consumes them.
--
-- $HOME, the JSON parser, and file I/O are all stubbed BEFORE the module is
-- required (it captures REGISTRY_PATH at load time), so the suite is hermetic
-- and needs no dkjson rock nor a real ~/.claude/domains.json.

local support = require "tests.support"

-- Pin $HOME so expand_home and REGISTRY_PATH are deterministic.
local real_getenv = os.getenv
os.getenv = function(key)
    if key == "HOME" then
        return "/home/test"
    end
    return real_getenv(key)
end

-- Stubbed file read: returns whatever raw string the case staged (content is
-- irrelevant because the JSON parser is stubbed too).
local fs_state = { raw = "{}" }
package.loaded["src.file-utils"] = {
    read_file = function(_)
        return fs_state.raw
    end,
    write_file = function()
        error "write_file is not used by domains"
    end,
}

-- Stubbed dkjson: returns the staged parse result / error in dkjson's
-- (obj, pos, err) shape.
local json_state = { result = nil, err = nil }
package.preload["dkjson"] = function()
    return {
        decode = function(_)
            return json_state.result, nil, json_state.err
        end,
    }
end

local domains = require "src.domains"

local function load_with(result, err)
    json_state.result = result
    json_state.err = err
    return domains.load()
end

local cases = {}

cases[#cases + 1] = {
    name = "domains are sorted by name with ~ expansion and default descriptions",
    fn = function()
        local loaded = load_with({
            beta = { path = "/srv/beta", description = "Beta vault" },
            alpha = { path = "~/alpha" },
        }, nil)
        support.assert_equal(loaded, {
            { name = "alpha", path = "/home/test/alpha", description = "" },
            { name = "beta", path = "/srv/beta", description = "Beta vault" },
        }, "sorted, expanded, default-described domains")
    end,
}

cases[#cases + 1] = {
    name = "a bare ~ path expands to $HOME",
    fn = function()
        local loaded = load_with({ home = { path = "~" } }, nil)
        support.assert_equal(loaded, {
            { name = "home", path = "/home/test", description = "" },
        }, "bare tilde expanded")
    end,
}

cases[#cases + 1] = {
    name = "a relative path is rejected at the boundary",
    fn = function()
        support.assert_raises(function()
            load_with({ bad = { path = "relative/vault" } }, nil)
        end, "must be absolute or ~-rooted", "relative path rejected")
    end,
}

cases[#cases + 1] = {
    name = "an empty registry is rejected",
    fn = function()
        support.assert_raises(function()
            load_with({}, nil)
        end, "No domains found", "empty registry rejected")
    end,
}

cases[#cases + 1] = {
    name = "a JSON parse error is surfaced",
    fn = function()
        support.assert_raises(function()
            load_with(nil, "unexpected token at line 3")
        end, "Failed to parse", "parse error surfaced")
    end,
}

cases[#cases + 1] = {
    name = "a non-object payload is rejected",
    fn = function()
        support.assert_raises(function()
            load_with("not an object", nil)
        end, "did not parse to a JSON object", "non-object payload rejected")
    end,
}

cases[#cases + 1] = {
    name = "a non-object domain entry is rejected",
    fn = function()
        support.assert_raises(function()
            load_with({ x = "scalar" }, nil)
        end, "is not an object", "scalar entry rejected")
    end,
}

cases[#cases + 1] = {
    name = "a domain entry missing its path is rejected",
    fn = function()
        support.assert_raises(function()
            load_with({ x = {} }, nil)
        end, "is missing a 'path'", "pathless entry rejected")
    end,
}

return { name = "domains", cases = cases }
