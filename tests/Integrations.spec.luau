--[[
    Unit tests for the storybook adapters (integrations/Flipbook.luau,
    integrations/UILabs.luau), run outside Roblox via Lune:

        lune run tests/Integrations.spec.luau

    These drive each adapter exactly the way the real plugin would: Flipbook
    calls story.story(parent, props) once and later calls the returned
    cleanup function; UI Labs calls story.render(props) once and pushes
    later control edits through props.subscribe instead. Neither Flipbook
    nor UI Labs is actually installed here — there's nothing to install,
    since both are Roblox Studio plugins — so this fakes just the calling
    convention each one documents, not the plugin itself.
]]

local Harness = require("./harness")
local makeEnv = require("./mocks/env")
local FakeInstance = require("./mocks/Instance")

task = require("@lune/task") :: any -- luau: intentional global assignment, read by Fragment.luau
local process = require("@lune/process")

local robloxLib = require("@lune/roblox")
Vector2 = robloxLib.Vector2 :: any -- luau: intentional global assignment
Vector3 = robloxLib.Vector3 :: any -- luau: intentional global assignment
UDim2 = robloxLib.UDim2 :: any -- luau: intentional global assignment
Color3 = robloxLib.Color3 :: any -- luau: intentional global assignment
Instance = { new = FakeInstance.new } :: any -- luau: intentional global assignment

local env = makeEnv()
game = env.game :: any -- luau: intentional global assignment, read by Fragment.luau

local Fragment = require("../src/Fragment")
local Flipbook = require("../src/Fragment/Integrations/Flipbook")
local UILabs = require("../src/Fragment/Integrations/UILabs")

Harness.test("Flipbook adapter mounts into the given parent and renders controls", function()
    local parent = FakeInstance.new("Frame", "FlipbookParent")

    local story = Flipbook.wrap(Fragment, function(element, controls)
        element.Name = `Rendered_{controls.text}`
    end, { text = "Hello" })

    local cleanup = story.story(parent, { controls = { text = "Hello" } })

    Harness.assertEqual(parent.Name, "Rendered_Hello", "the renderer should have run against the given parent")
    Harness.assertTrue(type(cleanup) == "function", "story() should return a cleanup function")

    cleanup()
end)

Harness.test("Flipbook adapter's cleanup actually unmounts (no leaked store subscription)", function()
    local store = Fragment.createStore("FlipbookLeakStore", function(set, get)
        return { Value = 0, bump = function() set({ Value = get().Value + 1 }) end }
    end)

    local parent = FakeInstance.new("Frame", "FlipbookParent2")
    local renders = 0

    local story = Flipbook.wrap(Fragment, function()
        Fragment.useStore("FlipbookLeakStore")
        renders += 1
    end, {})

    local cleanup = story.story(parent, { controls = {} })
    Harness.assertEqual(renders, 1, "story() should render once immediately")

    cleanup()
    store.bump()
    task.wait()

    Harness.assertEqual(renders, 1, "after cleanup, a store the story read from must not re-render it")
end)

Harness.test("UI Labs adapter renders once, then re-renders live on subscribe()", function()
    local target = FakeInstance.new("Frame", "UILabsTarget")
    local listener: ((any) -> ())? = nil

    local fakeProps = {
        target = target,
        controls = { Visible = true },
        subscribe = function(fn: (any) -> ())
            listener = fn
            return function() listener = nil end
        end,
    }

    local renders = {}
    local story = UILabs.wrap(Fragment, function(element, controls)
        element.Visible = controls.Visible
        table.insert(renders, controls.Visible)
    end, { Visible = true })

    local cleanup = story.render(fakeProps)
    Harness.assertEqual(#renders, 1, "render() should run the story once immediately")
    Harness.assertEqual(target.Visible, true, "the initial controls should have been applied")

    -- Simulate dragging the "Visible" control off in the UI Labs panel.
    Harness.assertTrue(listener ~= nil, "render() should have called props.subscribe")
    ;(listener :: any)({ Visible = false })

    Harness.assertEqual(#renders, 2, "a subscribe() callback should re-render exactly once per edit")
    Harness.assertEqual(target.Visible, false, "the re-render should apply the new control value")

    cleanup()
    Harness.assertTrue(listener == nil, "cleanup should call the unsubscribe function returned by subscribe()")
end)

local ok = Harness.summary()
process.exit(if ok then 0 else 1)
