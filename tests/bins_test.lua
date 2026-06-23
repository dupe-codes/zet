-- Tests for src/bins.lua.
--
-- Goal: verify note-type resolution — the built-in defaults, an optional
-- per-vault `meta/configs/zet-bins.yaml` that overrides a default IN PLACE (by
-- tag) or APPENDS a custom type, and the boundary assertions guarding a
-- malformed config. We assert the whole ordered result list because order is
-- load-bearing (it drives the dropdown), and a per-field check would miss an
-- override that duplicated rather than replaced.
--
-- bins reads the config through real `io.open` (file_exists) and `file-utils`,
-- so each case writes a real temp vault on disk; the YAML parser is stubbed so
-- the suite needs no rocks and the parsed shape is controlled per case.

local support = require "tests.support"

-- Stubbed YAML parser: returns whatever the current case staged. Installed via
-- package.preload so bins binds it at require time below.
local yaml_state = { result = nil }
package.preload["yaml"] = function()
    return {
        eval = function(_)
            return yaml_state.result
        end,
    }
end

local bins = require "src.bins"

local DEFAULTS = {
    { tag = "draft", bin = "chassis/knowledge/inbox", template = "meta/templates/draft.md" },
    { tag = "codex", bin = "chassis/knowledge/codex", template = "meta/templates/codex.md" },
}

-- Create a throwaway vault dir. When `config_present` is true a placeholder
-- zet-bins.yaml is written so file_exists() succeeds (its bytes are irrelevant
-- because the YAML parser is stubbed). Returns the vault path.
local function make_vault(config_present)
    local base = os.tmpname()
    os.remove(base)
    local vault = base .. "_vault"
    if config_present then
        os.execute("mkdir -p '" .. vault .. "/meta/configs'")
        local file = assert(io.open(vault .. "/meta/configs/zet-bins.yaml", "w"))
        file:write "# stubbed parser ignores this\n"
        file:close()
    else
        os.execute("mkdir -p '" .. vault .. "'")
    end
    return vault
end

local function cleanup(vault)
    os.execute("rm -rf '" .. vault .. "'")
end

local cases = {}

cases[#cases + 1] = {
    name = "no config yields the two built-in defaults in order",
    fn = function()
        local vault = make_vault(false)
        local resolved = bins.resolve(vault)
        cleanup(vault)
        support.assert_equal(resolved, DEFAULTS, "default note types")
    end,
}

cases[#cases + 1] = {
    name = "a custom entry overrides a matching default in place, order preserved",
    fn = function()
        local vault = make_vault(true)
        yaml_state.result = {
            bins = {
                { tag = "codex", bin = "vault/codex", template = "tpl/codex.md" },
                { tag = "journal", bin = "vault/journal", template = "tpl/journal.md" },
            },
        }
        local resolved = bins.resolve(vault)
        cleanup(vault)
        support.assert_equal(resolved, {
            { tag = "draft", bin = "chassis/knowledge/inbox", template = "meta/templates/draft.md" },
            { tag = "codex", bin = "vault/codex", template = "tpl/codex.md" },
            { tag = "journal", bin = "vault/journal", template = "tpl/journal.md" },
        }, "codex overridden in place, journal appended")
    end,
}

cases[#cases + 1] = {
    name = "a brand-new tag is appended after the defaults",
    fn = function()
        local vault = make_vault(true)
        yaml_state.result = {
            bins = {
                { tag = "journal", bin = "vault/journal", template = "tpl/journal.md" },
            },
        }
        local resolved = bins.resolve(vault)
        cleanup(vault)
        support.assert_equal(resolved, {
            { tag = "draft", bin = "chassis/knowledge/inbox", template = "meta/templates/draft.md" },
            { tag = "codex", bin = "chassis/knowledge/codex", template = "meta/templates/codex.md" },
            { tag = "journal", bin = "vault/journal", template = "tpl/journal.md" },
        }, "journal appended")
    end,
}

cases[#cases + 1] = {
    name = "a config that does not parse to a mapping is rejected",
    fn = function()
        local vault = make_vault(true)
        yaml_state.result = "not a table"
        support.assert_raises(function()
            bins.resolve(vault)
        end, "expected a mapping", "non-mapping config rejected")
        cleanup(vault)
    end,
}

cases[#cases + 1] = {
    name = "a bin entry missing its tag is rejected",
    fn = function()
        local vault = make_vault(true)
        yaml_state.result = { bins = { { bin = "vault/x", template = "tpl/x.md" } } }
        support.assert_raises(function()
            bins.resolve(vault)
        end, "needs a 'tag'", "tagless bin rejected")
        cleanup(vault)
    end,
}

cases[#cases + 1] = {
    name = "a bin entry missing its template is rejected",
    fn = function()
        local vault = make_vault(true)
        yaml_state.result = { bins = { { tag = "journal", bin = "vault/journal" } } }
        support.assert_raises(function()
            bins.resolve(vault)
        end, "needs a 'template'", "templateless bin rejected")
        cleanup(vault)
    end,
}

cases[#cases + 1] = {
    name = "resolve asserts on an empty vault path",
    fn = function()
        support.assert_raises(function()
            bins.resolve("")
        end, "requires a vault path", "empty vault path rejected")
    end,
}

return { name = "bins", cases = cases }
