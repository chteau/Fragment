--[[
    Unit tests for Fragment.luau, run outside Roblox via Lune:

        lune run tests/Fragment.spec.luau

    Fragment reads `game`/`Players`/`TweenService` as plain globals (both at
    module load time and, for `game`, inside useComponent), so this file
    assigns a fake `game` to the real global BEFORE requiring Fragment —
    Lune shares one global table across required modules, same as Roblox
    sharing one global environment across scripts.

    Coverage here is intentionally narrow: it targets the behavior added or
    changed across a few rounds of work — the Effect() dependency array, the
    Render() re-entrancy/batching fixes, and the newer declarative-create/
    list/spring/mount/attribute primitives — plus a couple of smoke tests
    (bind, store subscriptions) to make sure the surrounding render pipeline
    wasn't broken along the way. It is not a full spec of Fragment.
]]

local Harness = require("./harness")
local makeEnv = require("./mocks/env")
local FakeInstance = require("./mocks/Instance")

-- Roblox exposes `task` and `process`-like globals (task always; `process`
-- doesn't exist in Roblox but we need an exit code here); Lune exposes the
-- same functionality as named library modules instead. Fragment.luau calls
-- bare `task.spawn`/`task.wait` as globals (matching Roblox), so promote it
-- to a global here too, same as `game` below.
task = require("@lune/task") :: any -- luau: intentional global assignment, read by Fragment.luau
local process = require("@lune/process")

-- Lune's @lune/roblox module exposes Roblox's geometry/color datatypes as
-- fields, not globals (it's built for editing .rbxl files, not scripting).
-- Fragment.spring() uses Vector2/Vector3/UDim2/Color3 as bare globals, same
-- as real Roblox, so promote the ones the tests need the same way as `game`.
local robloxLib = require("@lune/roblox")
Vector2 = robloxLib.Vector2 :: any -- luau: intentional global assignment
Vector3 = robloxLib.Vector3 :: any -- luau: intentional global assignment
UDim2 = robloxLib.UDim2 :: any -- luau: intentional global assignment
Color3 = robloxLib.Color3 :: any -- luau: intentional global assignment

-- Fragment.create calls bare `Instance.new(...)`, same as real Roblox —
-- route it to our FakeInstance so create() produces mockable Instances too.
Instance = { new = FakeInstance.new } :: any -- luau: intentional global assignment

local env = makeEnv()
game = env.game :: any -- luau: intentional global assignment, read by Fragment.luau

local Fragment = require("../src/Fragment")

--[[
    Mounts a bare ScreenGui directly under the fake PlayerGui so a handle
    whose path is { name } resolves successfully.
]]
local function mountScreenGui(name: string): any
    local screenGui = FakeInstance.new("ScreenGui", name)
    env.playerGui:AddChild(screenGui)
    return screenGui
end

Harness.test("Effect with no deps re-runs on every render", function()
    mountScreenGui("NoDepsGui")
    local handle = Fragment.newHandle("NoDepsHandle", { "NoDepsGui" })

    local runs, cleanups = 0, 0
    handle(function()
        handle.Effect(function()
            runs += 1
            return function() cleanups += 1 end
        end)
    end)

    handle:Render()
    handle:Render()
    handle:Render()

    Harness.assertEqual(runs, 3, "effect without deps should run on every render")
    Harness.assertEqual(cleanups, 2, "the previous effect should tear down before each rerun")
end)

Harness.test("Effect skips teardown/rerun when deps are unchanged", function()
    mountScreenGui("StableDepsGui")
    local handle = Fragment.newHandle("StableDepsHandle", { "StableDepsGui" })

    local runs, cleanups = 0, 0
    local depValue = 1
    handle(function()
        handle.Effect(function()
            runs += 1
            return function() cleanups += 1 end
        end, { depValue })
    end)

    handle:Render()
    handle:Render()
    handle:Render()

    Harness.assertEqual(runs, 1, "the effect should not rerun while its deps are unchanged")
    Harness.assertEqual(cleanups, 0, "the effect should not tear down while its deps are unchanged")
end)

Harness.test("Effect reruns exactly when its deps change", function()
    mountScreenGui("ChangingDepsGui")
    local handle = Fragment.newHandle("ChangingDepsHandle", { "ChangingDepsGui" })

    local runs, cleanups = 0, 0
    local depValue = 1
    handle(function()
        handle.Effect(function()
            runs += 1
            return function() cleanups += 1 end
        end, { depValue })
    end)

    handle:Render()      -- depValue = 1 -> runs
    depValue = 2
    handle:Render()      -- depValue = 2 (changed) -> reruns
    handle:Render()      -- depValue still 2 (unchanged) -> skips

    Harness.assertEqual(runs, 2, "the effect should rerun only when deps actually change")
    Harness.assertEqual(cleanups, 1, "only the stale (pre-change) effect should be torn down")
end)

Harness.test("a Render() called synchronously during an active render is queued, not dropped", function()
    mountScreenGui("ReentrantGui")
    local handle = Fragment.newHandle("ReentrantHandle", { "ReentrantGui" })

    local renderCount = 0
    local triggeredNested = false
    handle(function()
        renderCount += 1
        if not triggeredNested then
            triggeredNested = true
            -- Simulates a store/context update firing synchronously from
            -- inside this very render pass (e.g. from an Action) — must not
            -- be silently swallowed by the re-entrancy guard.
            handle:Render()
        end
    end)

    handle:Render()

    Harness.assertEqual(renderCount, 2, "the nested Render() call should produce a second pass")
    Harness.assertEqual(handle._rendering, false, "the rendering flag must clear once every queued pass finishes")
end)

Harness.test("the rendering flag clears even when the element fails to resolve", function()
    local handle = Fragment.newHandle("UnresolvableHandle", { "DoesNotExist" })
    handle(function() end)

    handle:Render()

    Harness.assertEqual(handle._rendering, false, "a resolve failure must not leave the handle stuck mid-render forever")
end)

Harness.test("bind() setState schedules exactly one re-render", function()
    mountScreenGui("BindGui")
    local handle = Fragment.newHandle("BindHandle", { "BindGui" })

    local observed = {}
    local setCount: ((number) -> ())? = nil

    handle(function()
        local count, setCountFn = handle:bind(0)
        setCount = setCountFn
        table.insert(observed, count())
    end)

    handle:Render()
    ;(setCount :: any)(5)

    -- bind()'s setter defers the re-render via task.spawn; let it run.
    task.wait()

    Harness.assertEqual(#observed, 2, "setState should trigger exactly one additional render")
    Harness.assertEqual(observed[2], 5, "the second render should observe the updated state")
end)

Harness.test("createStore notifies every subscribed handle on change", function()
    mountScreenGui("StoreGui")
    local handle = Fragment.newHandle("StoreHandle", { "StoreGui" })

    local store = Fragment.createStore("CounterStore", function(set, get)
        return {
            Count = 0,
            increment = function()
                set({ Count = get().Count + 1 })
            end,
        }
    end)

    local seen = {}
    handle(function()
        local s = Fragment.useStore("CounterStore")
        table.insert(seen, s.Count)
    end)

    handle:Render()
    store.increment()
    task.wait() -- store updates are batched via scheduleRender's task.defer

    Harness.assertEqual(#seen, 2, "a store change should re-render every subscribed handle")
    Harness.assertEqual(seen[2], 1, "the re-render should observe the updated store value")
end)

Harness.test("multiple setState calls in the same tick are batched into one render", function()
    mountScreenGui("BatchGui")
    local handle = Fragment.newHandle("BatchHandle", { "BatchGui" })

    local observed = {}
    local setA: ((number) -> ())? = nil
    local setB: ((number) -> ())? = nil

    handle(function()
        local a, setAFn = handle:bind(0)
        local b, setBFn = handle:bind(0)
        setA, setB = setAFn, setBFn
        table.insert(observed, { a = a(), b = b() })
    end)

    handle:Render()

    -- Both setters fire synchronously, in the same tick, same as calling
    -- them one after another inside a single Action.
    ;(setA :: any)(1)
    ;(setB :: any)(2)
    task.wait()

    Harness.assertEqual(#observed, 2, "two setState calls in one tick should produce exactly one extra render, not two")
    Harness.assertEqual(observed[2].a, 1, "the batched render should see both updates")
    Harness.assertEqual(observed[2].b, 2, "the batched render should see both updates")
end)

Harness.test("a store update and a context update to the same handle in one tick are batched together", function()
    mountScreenGui("CrossBatchGui")
    local handle = Fragment.newHandle("CrossBatchHandle", { "CrossBatchGui" })

    local store = Fragment.createStore("CrossBatchStore", function(set, get)
        return {
            Value = 0,
            bump = function() set({ Value = get().Value + 1 }) end,
        }
    end)
    local ctx = Fragment.createContext({ flag = false })

    local observed = {}
    handle(function()
        local s = Fragment.useStore("CrossBatchStore")
        local c = handle:pull(ctx)
        table.insert(observed, { value = s.Value, flag = c.flag })
    end)

    handle:Render()

    store.bump()
    ctx:patch({ flag = true })
    task.wait()

    Harness.assertEqual(#observed, 2, "a store update and a context update in the same tick should batch into one render")
    Harness.assertEqual(observed[2].value, 1, "the batched render should see the store update")
    Harness.assertEqual(observed[2].flag, true, "the batched render should see the context update")
end)

Harness.test("Fragment.create builds an Instance, applies props, and wires OnEvent", function()
    local clicked = 0
    local btn = Fragment.create("TextButton", {
        Name = "MyButton",
        Text = "Click me",
        [Fragment.OnEvent("Activated")] = function() clicked += 1 end,
    })

    Harness.assertEqual(btn.ClassName, "TextButton", "create should build the requested class")
    Harness.assertEqual(btn.Name, "MyButton", "create should apply string-keyed props")
    Harness.assertEqual(btn.Text, "Click me", "create should apply string-keyed props")

    btn.Activated:Fire()
    Harness.assertEqual(clicked, 1, "an [OnEvent(...)] handler should be connected during create")
end)

Harness.test("Fragment.create parents [Fragment.Children] under the new Instance", function()
    local label = Fragment.create("TextLabel", { Text = "child" })
    local single = Fragment.create("TextLabel", { Text = "only child" })

    local frame = Fragment.create("Frame", {
        [Fragment.Children] = { Title = label },
    })
    local wrapper = Fragment.create("Frame", {
        [Fragment.Children] = { single },
    })

    Harness.assertEqual(label.Parent, frame, "a named entry in Children should be parented under the new Instance")
    Harness.assertEqual(label.Name, "Title", "a string key in the Children map should rename its child")
    Harness.assertEqual(frame:FindFirstChild("Title"), label, "the parented child should be findable by its new name")
    Harness.assertEqual(single.Parent, wrapper, "an anonymous (array-form) entry in Children should still be parented")
end)

Harness.test("container.Each diffs a keyed list the same way UpsertChild does by hand", function()
    local screenGui = mountScreenGui("EachGui")
    local listFrame = FakeInstance.new("Frame", "List")
    screenGui:AddChild(listFrame)

    local handle = Fragment.newHandle("EachHandle", { "EachGui" })
    local items = { "a", "b", "c" }

    handle(function()
        local container = handle.RegisterContainer(listFrame)
        container.Each(items, function(item) return item end, function(item)
            return Fragment.create("TextLabel", { Name = item, Text = item })
        end)
    end)

    handle:Render()
    Harness.assertEqual(#listFrame:GetChildren(), 3, "Each should render one child per item")

    items = { "a", "c" } -- "b" removed
    handle:Render()
    Harness.assertEqual(#listFrame:GetChildren(), 2, "Each should remove children for keys no longer present")
    Harness.assertTrue(listFrame:FindFirstChild("a") ~= nil, "surviving keys should still be present")
    Harness.assertTrue(listFrame:FindFirstChild("b") == nil, "the removed key's child should be gone")
end)

Harness.test("handle:spring animates toward its target and settles exactly on it", function()
    mountScreenGui("SpringGui")
    local handle = Fragment.newHandle("SpringHandle", { "SpringGui" })

    local observed = {}
    local setTarget: ((number) -> ())? = nil

    handle(function()
        local value, setTargetFn = handle:spring(0, { frequency = 4, damping = 1 })
        setTarget = setTargetFn
        table.insert(observed, value())
    end)

    handle:Render()
    ;(setTarget :: any)(10)

    -- Step the shared Heartbeat enough simulated seconds for a critically
    -- damped spring at this frequency to settle well within its target.
    for _ = 1, 300 do
        env.heartbeat:Fire(1 / 60)
    end
    task.wait()

    Harness.assertEqual(#observed, 2, "settling should be batched into exactly one extra render, same as any other scheduleRender call")
    Harness.assertEqual(observed[2], 10, "the spring should settle exactly on its target, not just near it")
end)

Harness.test("Fragment.mount renders into an Instance without needing a PlayerGui path", function()
    local detached = FakeInstance.new("Frame", "Detached") -- never parented anywhere
    local renders = 0

    local handle = Fragment.mount(detached, function(element)
        renders += 1
        element.Name = "MountedByFragment"
    end)

    Harness.assertEqual(renders, 1, "mount should render immediately")
    Harness.assertEqual(detached.Name, "MountedByFragment", "the renderer should run against the given container")

    handle:Unmount()
end)

Harness.test("Unmount removes a mounted handle from every store it subscribed to", function()
    local store = Fragment.createStore("MountLeakStore", function(set, get)
        return { Value = 0, bump = function() set({ Value = get().Value + 1 }) end }
    end)

    local detached = FakeInstance.new("Frame", "LeakCheck")
    local renders = 0

    local handle = Fragment.mount(detached, function()
        Fragment.useStore("MountLeakStore")
        renders += 1
    end)

    Harness.assertEqual(renders, 1, "mount should render immediately, subscribing to the store along the way")

    handle:Unmount()
    store.bump()
    task.wait()

    Harness.assertEqual(renders, 1, "an unmounted handle must not still be re-rendered when its old store changes")
end)

Harness.test("handle:attribute reads a replicated attribute and reacts to changes", function()
    mountScreenGui("AttrGui")
    local handle = Fragment.newHandle("AttrHandle", { "AttrGui" })

    local source = FakeInstance.new("Frame", "AttrSource")
    source:SetAttribute("Coins", 5)

    local observed = {}
    handle(function()
        local getCoins = handle:attribute(source, "Coins")
        table.insert(observed, getCoins())
    end)

    handle:Render()
    Harness.assertEqual(observed[1], 5, "attribute() should read the current value immediately")

    source:SetAttribute("Coins", 9)
    task.wait()

    Harness.assertEqual(#observed, 2, "an attribute change should trigger exactly one extra render")
    Harness.assertEqual(observed[2], 9, "the re-render should observe the new attribute value")
end)

local ok = Harness.summary()
process.exit(if ok then 0 else 1)

