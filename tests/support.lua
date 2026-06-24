-- Minimal test support: deep-equality assertions and a tiny runner.
--
-- The project ships no test framework, so this is a dependency-free harness
-- that runs under plain Lua / LuaJIT (the LÖVE runtime). It deliberately has
-- no I/O of its own beyond stdout so tests stay hermetic. Test files return a
-- list of `{ name = string, fn = function }` cases; `support.run` executes
-- them, reports pass/fail, and the runner exits non-zero on any failure.

local M = {}

-- Recursive structural equality for the values our modules return: strings,
-- numbers, booleans, nil, and (possibly nested) tables used as lists/maps.
-- Whole-payload assertions depend on this, per the testing conventions.
local function deep_equal(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not deep_equal(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

M.deep_equal = deep_equal

-- Render a value for failure messages. Tables are shown shallowly enough to
-- diagnose a mismatch without pulling in a serialization dependency.
local function show(value)
    if type(value) ~= "table" then
        return string.format("%q", tostring(value))
    end
    local parts = {}
    for key, inner in pairs(value) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(inner)
    end
    table.sort(parts)
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Assert two values are structurally equal; raise with both sides on failure.
function M.assert_equal(actual, expected, label)
    assert(type(label) == "string" and label ~= "", "assert_equal needs a label")
    if not deep_equal(actual, expected) then
        error(
            label
                .. "\n  expected: "
                .. show(expected)
                .. "\n  actual:   "
                .. show(actual),
            2
        )
    end
end

-- Assert `fn` raises, and that the error message contains `needle` (a plain
-- substring, not a pattern). Asserts both that it failed AND why.
function M.assert_raises(fn, needle, label)
    assert(type(fn) == "function", "assert_raises needs a function")
    assert(type(needle) == "string", "assert_raises needs a needle")
    assert(type(label) == "string" and label ~= "", "assert_raises needs a label")
    local ok, err = pcall(fn)
    if ok then
        error(label .. "\n  expected an error, but the call succeeded", 2)
    end
    if not tostring(err):find(needle, 1, true) then
        error(
            label
                .. "\n  expected error containing: "
                .. needle
                .. "\n  actual error:             "
                .. tostring(err),
            2
        )
    end
end

-- Run a list of cases, printing one line each. Returns (passed, failed).
function M.run(suite_name, cases)
    assert(type(suite_name) == "string", "run needs a suite name")
    assert(type(cases) == "table", "run needs a list of cases")
    local passed, failed = 0, 0
    print("# " .. suite_name)
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.fn)
        if ok then
            passed = passed + 1
            print("  ok   - " .. case.name)
        else
            failed = failed + 1
            print("  FAIL - " .. case.name)
            print("         " .. tostring(err):gsub("\n", "\n         "))
        end
    end
    return passed, failed
end

return M
