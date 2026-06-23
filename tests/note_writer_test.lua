-- Tests for src/note_writer.lua.
--
-- Goal: exercise the pure string-munging that turns a vault template plus user
-- input into a finished note. We assert WHOLE rendered payloads (not field
-- fragments) because the renderer's job is the exact bytes written to disk, and
-- the bugs that bite here are whitespace/quoting/ordering ones a field check
-- would miss. Coverage spans the happy path, the YAML-escaping edge that
-- corrupts frontmatter (description with a colon), tag de-duplication and order,
-- date substitution across the whole document, and the degenerate template
-- shapes that must warn rather than silently drop the user's metadata.
--
-- Dependencies are stubbed so the module loads with no rocks and no real files:
--   * `src.file-utils` returns a template string the test controls.
--   * `os.date` is pinned to a fixed clock for deterministic date assertions.

local support = require "tests.support"

-- Controllable file-system stub: read_file hands back whatever template the
-- current case installed. Bound by note_writer at load time below.
local fs = { template = "" }
package.loaded["src.file-utils"] = {
    read_file = function(_)
        return fs.template
    end,
    write_file = function()
        error "write_file is not used by note_writer"
    end,
}

-- Pin the clock. note_writer converts moment formats to strftime, so we map the
-- strftime strings its tests provoke; an unmapped format trips a loud error so
-- a test can never silently assert against the wrong date.
local CLOCK = { ["%Y-%m-%d"] = "2026-06-23", ["%Y"] = "2026" }
os.date = function(fmt)
    return CLOCK[fmt] or error("unexpected date format in test: " .. tostring(fmt))
end

local note_writer = require "src.note_writer"

-- Capture warnings emitted during a render so degenerate-input cases can assert
-- the user was told, rather than the input being swallowed.
local function render_capturing(template, fields)
    fs.template = template
    local warnings = {}
    local previous_warn = note_writer.warn
    note_writer.warn = function(message)
        warnings[#warnings + 1] = message
    end
    local ok, rendered = pcall(note_writer.render, "vault/meta/templates/t.md", fields)
    note_writer.warn = previous_warn
    assert(ok, "render unexpectedly failed: " .. tostring(rendered))
    return rendered, warnings
end

local BLOCK_TEMPLATE = table.concat({
    "---",
    "type: draft",
    "description:",
    "tags:",
    "  - inbox",
    "created_at: {{date:YYYY-MM-DD}}",
    "---",
    "",
    "# Heading",
    "",
}, "\n")

local cases = {}

cases[#cases + 1] = {
    name = "happy path merges description and tags, fills the date",
    fn = function()
        local rendered, warnings = render_capturing(BLOCK_TEMPLATE, {
            description = "My note",
            tags = { "inbox", "foo" },
            content = "",
        })
        local expected = table.concat({
            "---",
            "type: draft",
            "description: My note",
            "tags:",
            "  - inbox",
            "  - foo",
            "created_at: 2026-06-23",
            "---",
            "",
            "",
            "# Heading",
            "",
        }, "\n")
        support.assert_equal(rendered, expected, "rendered note")
        support.assert_equal(warnings, {}, "no warnings on the happy path")
    end,
}

cases[#cases + 1] = {
    name = "description with a colon is double-quoted, not left as broken YAML",
    fn = function()
        local rendered = render_capturing(BLOCK_TEMPLATE, {
            description = "Refactor: domain integration",
            tags = {},
            content = "",
        })
        local expected = table.concat({
            "---",
            "type: draft",
            'description: "Refactor: domain integration"',
            "tags:",
            "  - inbox",
            "created_at: 2026-06-23",
            "---",
            "",
            "",
            "# Heading",
            "",
        }, "\n")
        support.assert_equal(rendered, expected, "colon description quoted")
    end,
}

cases[#cases + 1] = {
    name = "description with quotes and backslash is escaped inside the quotes",
    fn = function()
        local rendered = render_capturing(BLOCK_TEMPLATE, {
            -- Value contains a colon-space (forces quoting), a literal " and a \.
            description = [[say: "hi\bye"]],
            tags = {},
            content = "",
        })
        -- Inside a double-quoted YAML scalar, \ -> \\ and " -> \".
        local expected_line = [[description: "say: \"hi\\bye\""]]
        local has_line = rendered:find(expected_line, 1, true) ~= nil
        support.assert_equal(has_line, true, "escaped description line present")
    end,
}

cases[#cases + 1] = {
    name = "description leading with an indicator character is quoted",
    fn = function()
        local rendered = render_capturing(BLOCK_TEMPLATE, {
            description = "- not a list item",
            tags = {},
            content = "",
        })
        local has_line = rendered:find('description: "- not a list item"', 1, true) ~= nil
        support.assert_equal(has_line, true, "leading-dash description quoted")
    end,
}

cases[#cases + 1] = {
    name = "duplicate tags are de-duplicated and template order is preserved",
    fn = function()
        local rendered = render_capturing(BLOCK_TEMPLATE, {
            description = "",
            tags = { "inbox", "alpha", "alpha", "beta" },
            content = "",
        })
        local expected = table.concat({
            "---",
            "type: draft",
            "description:",
            "tags:",
            "  - inbox",
            "  - alpha",
            "  - beta",
            "created_at: 2026-06-23",
            "---",
            "",
            "",
            "# Heading",
            "",
        }, "\n")
        support.assert_equal(rendered, expected, "deduped, ordered tags")
    end,
}

cases[#cases + 1] = {
    name = "a tag containing a colon is quoted so it stays a string, not a mapping",
    fn = function()
        -- Same YAML-corruption class as the description finding: an unquoted
        -- `- foo: bar` list item parses as a mapping, silently losing the tag.
        local rendered = render_capturing(BLOCK_TEMPLATE, {
            description = "",
            tags = { "needs: review" },
            content = "",
        })
        local has_line = rendered:find('  - "needs: review"', 1, true) ~= nil
        support.assert_equal(has_line, true, "colon tag quoted as a scalar")
    end,
}

cases[#cases + 1] = {
    name = "date placeholders in the body are filled, not just the frontmatter",
    fn = function()
        local template = table.concat({
            "---",
            "type: draft",
            "description:",
            "tags:",
            "---",
            "",
            "Logged on {{date}} ({{date:YYYY}}).",
            "",
        }, "\n")
        local rendered = render_capturing(template, {
            description = "",
            tags = {},
            content = "Appended at {{date}}.",
        })
        local body_filled = rendered:find("Logged on 2026-06-23 (2026).", 1, true) ~= nil
        local content_filled = rendered:find("Appended at 2026-06-23.", 1, true) ~= nil
        support.assert_equal(
            { body_filled, content_filled },
            { true, true },
            "dates filled in body and appended content"
        )
    end,
}

cases[#cases + 1] = {
    name = "inline tags list warns instead of silently dropping user tags",
    fn = function()
        local template = table.concat({
            "---",
            "type: draft",
            "tags: [seed]",
            "---",
            "",
            "body",
            "",
        }, "\n")
        local rendered, warnings = render_capturing(template, {
            description = "",
            tags = { "foo", "bar" },
            content = "",
        })
        local line_preserved = rendered:find("tags: [seed]", 1, true) ~= nil
        support.assert_equal(line_preserved, true, "inline tags line preserved verbatim")
        support.assert_equal(#warnings, 1, "exactly one warning emitted")
        local mentions = warnings[1]:find("inline 'tags:'", 1, true) ~= nil
        support.assert_equal(mentions, true, "warning explains the inline-list cause")
    end,
}

cases[#cases + 1] = {
    name = "template without frontmatter warns and still appends content",
    fn = function()
        local template = "# Plain template, no frontmatter\n\nintro on {{date}}\n"
        local rendered, warnings = render_capturing(template, {
            description = "dropped",
            tags = { "dropped" },
            content = "appended body",
        })
        local expected = "# Plain template, no frontmatter\n\nintro on 2026-06-23\nappended body"
        support.assert_equal(rendered, expected, "verbatim body plus content, dates filled")
        support.assert_equal(#warnings, 1, "one warning about dropped metadata")
    end,
}

cases[#cases + 1] = {
    name = "frontmatter without a tags key gains an appended block for user tags",
    fn = function()
        local template = table.concat({
            "---",
            "type: draft",
            "description:",
            "---",
            "",
            "body",
            "",
        }, "\n")
        local rendered, warnings = render_capturing(template, {
            description = "",
            tags = { "x", "y", "x" },
            content = "",
        })
        local expected = table.concat({
            "---",
            "type: draft",
            "description:",
            "tags:",
            "  - x",
            "  - y",
            "---",
            "",
            "",
            "body",
            "",
        }, "\n")
        support.assert_equal(rendered, expected, "appended deduped tags block")
        support.assert_equal(warnings, {}, "no warning: tags were preserved, not dropped")
    end,
}

cases[#cases + 1] = {
    name = "empty description leaves the template's description key untouched",
    fn = function()
        local rendered = render_capturing(BLOCK_TEMPLATE, {
            description = "   ",
            tags = {},
            content = "",
        })
        local untouched = rendered:find("\ndescription:\n", 1, true) ~= nil
        support.assert_equal(untouched, true, "blank description not written")
    end,
}

cases[#cases + 1] = {
    name = "render asserts on a missing template path",
    fn = function()
        support.assert_raises(function()
            note_writer.render("", { description = "", tags = {}, content = "" })
        end, "requires a template path", "empty path rejected")
    end,
}

return { name = "note_writer", cases = cases }
