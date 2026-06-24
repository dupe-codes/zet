-- Test entry point. Run from the project root:
--
--     luajit tests/run.lua        (LÖVE's runtime — preferred)
--     lua tests/run.lua
--     make test
--
-- Requires each *_test.lua suite, runs every case, prints a TAP-ish summary,
-- and exits non-zero if anything failed so `make test` and CI can gate on it.
-- Each suite installs its own dependency stubs before requiring its module, so
-- ordering here is irrelevant and the suites do not interfere.

package.path = "./?.lua;" .. package.path

local support = require "tests.support"

local SUITES = {
    "tests.note_writer_test",
    "tests.bins_test",
    "tests.domains_test",
}

local total_passed, total_failed = 0, 0
for _, suite_module in ipairs(SUITES) do
    local suite = require(suite_module)
    local passed, failed = support.run(suite.name, suite.cases)
    total_passed = total_passed + passed
    total_failed = total_failed + failed
end

print(string.format("\n%d passed, %d failed", total_passed, total_failed))
if total_failed > 0 then
    os.exit(1)
end
