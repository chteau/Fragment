--[[
    A deliberately tiny test runner — Fragment has no test dependency today,
    and pulling in a full framework for ~10 assertions isn't worth it. Each
    `test()` call runs immediately (not collected and run later), so test
    order in the spec file is the execution order.
]]

local Harness = {}

local passed = 0
local failed = 0
local failures: { string } = {}

function Harness.test(name: string, fn: () -> ())
    local ok, err = pcall(fn)
    if ok then
        passed += 1
        print(`  ok   - {name}`)
    else
        failed += 1
        table.insert(failures, `{name}: {err}`)
        print(`  FAIL - {name}`)
        print(`         {err}`)
    end
end

function Harness.assertEqual(actual: any, expected: any, message: string?)
    if actual ~= expected then
        error(`{message or "assertEqual failed"} — expected {tostring(expected)}, got {tostring(actual)}`, 2)
    end
end

function Harness.assertTrue(value: any, message: string?)
    if not value then
        error(message or "expected value to be truthy", 2)
    end
end

--[[
    Prints the run summary and returns whether every test passed.
]]
function Harness.summary(): boolean
    print(`\n{passed} passed, {failed} failed`)
    if failed > 0 then
        print("\nFailures:")
        for _, f in ipairs(failures) do
            print(`  - {f}`)
        end
    end
    return failed == 0
end

return Harness
