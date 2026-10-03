--[[

      kkkkkŸŸ®Ÿ                ŸŸŸŸŸŸkkk
     ÝkÝkkkkkŸkŸŸŸŸŸ      S®®®®®ŸŸŸŸŸkkŸŸ
     ÝÝÝkkkÝÝŸkŸkkŸŸŸŸŸ®®Ÿ®®Ÿ®ŸŸŸŸŸŸkkkŸk
     §§§ÝÝkÝÝkÝŸkŸŸkŸŸŸ®®®Ÿ®Ÿ®ŸŸŸŸŸŸkkŸkk
      û§§§§ÝkÝÝkÝkkŸŸŸŸŸŸkkŸŸ®ŸŸŸŸŸŸkkkk
       ûû§§§§§ÝÝÝÝÝkkŸkkŸŸkŸŸkŸŸŸkkkkÝÝ
       ûhûûûûû§§ÝÝÝÝkÝkÝkŸkkŸkÝkkkkkÝÝÝ
        hûûûûûûûûûÝ§ÝÝÝkÝkkkÝkÝÝkkÝÝÝÝ
         hûûûhûûûûûû§§Ý§ÝÝÝkkÝkÝÝÝÝÝÝ
         àààûûûûûûûûûûûû§Ý§ÝÝÝ§Ý§ÝÝ§Ý
         ÇÇàhhhàûûhûûûûûûû§§û§Ýû§û§§û
        äšÇÇàÇàhàhhhûhûûûûûûûû§§ûûûûûû
       ääšššššÇÇhààhhhhhhhhûûûûûûûûûûhû
       ääääšäšÇÇÇÇàààààhàhhàûhhûûhhhhàà
      äPäääääšššššÇÇàÇàààÇhÇààhhhhhààààà
     PääPPäääääššššššÇÇÇÇàÇÇÇÇààààààààÇšš
     PPPPPääPäääääššääÇšššššÇÇààààÇÇÇÇÇšš
     ZPPPPPääääääääš      šššššÇÇÇÇšššššä
      ZZZPPPPää                šÇššššääš

    @Cheeteau - 2026

    A simple module to manage Roblox's UI components inspired by React.
    Supports state management, effects, declarative rendering and more.

    ----------------------------------------------------------------------------

    MIT License

    Copyright (c) 2026 Cheeteau

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Type definitions
export type Data = { [string]: any }
export type Renderer = (element: Instance, data: Data) -> ()
export type EffectFn = () -> (() -> ())?
export type ActionFn = (...any) -> any

-- Internal registries and states
local _registry:      { [string]: any } = {}
local _data:          Data = {}
local _failedHandles: { [string]: true } = {}
local _handleCount:   number = 0

local _components:    { [string]: any } = {}

-- Store related variables
local _stores:           { [string]: any } = {}
local _storeSubscribers: { [string]: { [string]: any } } = {}
local _activeHandle:     any = nil

-- Context system counter
local _contextCount: number = 0

-- Spring physics: one shared Heartbeat connection steps every active spring
-- (handle:spring()), rather than one connection per spring. Entries remove
-- themselves once settled, and the connection tears itself down when none
-- are left.
local _springs:         { [string]: any } = {}
local _springHeartbeat: RBXScriptConnection? = nil

-- Mounted (ad-hoc) handles, e.g. from Fragment.mount — counted separately
-- from newHandle's _handleCount since they're never added to _registry.
local _mountCount: number = 0

-- Component instance lifecycle
-- Each live component instance (parented into a container) owns a ComponentInstance
-- that manages its own Effects, Connections, bind/derive/hold slots, and Once flag.
-- Weak keys let the Lua GC reclaim entries for instances that were destroyed without
-- going through a container (safety net — the real cleanup is Destroying:Connect).
local _componentInstanceCount: number = 0
local _componentInstances: { [Instance]: any } = setmetatable({}, { __mode = "k" })

-- Forward-declared so makeContainer closures can reference it before it is assigned.
local renderComponentInstance: (ci: any, props: { [string]: any }) -> ()

-- Marker for uninitialized  values
local UNSET = {}

-- Helpers
--[[
    Performs a shallow comparison between two tables.

    @param {any} a - First table to compare
    @param {any} b - Second table to compare
    @returns boolean - True if tables are shallow equal, false otherwise
]]
local function shallowEqual(a: { any }, b: { any }): boolean
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if (b :: any)[k] ~= v then return false end
    end
    for k, v in pairs(b) do
        if (a :: any)[k] ~= v then return false end
    end
    return true
end

--[[
    Applies one render pass' worth of Effect() calls against the previous
    pass' cleanups/deps, mirroring useEffect()'s dependency-array semantics:
    an effect whose deps are shallow-equal to last pass' deps is left alone
    (no cleanup, no rerun) — only effects with no deps, or with changed deps,
    tear down and rerun. Effects are matched by call order (position), which
    is why Effect() calls must happen in the same order on every render, same
    as bind/derive/hold slots.

    @param string name - owner name (handle or component instance), for warnings
    @param { [number]: { fn: EffectFn, deps: {any}? } } effects - this pass' effects, in call order
    @param { [number]: () -> () } prevCleanups - cleanups stored from the previous pass
    @param { [number]: ({any}?) } prevDeps - deps stored from the previous pass
    @returns { [number]: () -> () }, { [number]: ({any}?) } - cleanups and deps for this pass
]]
local function runEffects(
    name: string,
    effects: { [number]: { fn: EffectFn, deps: { any }? } },
    prevCleanups: { [number]: () -> () },
    prevDeps: { [number]: { any }? }
): ({ [number]: () -> () }, { [number]: { any }? })
    local newCleanups: { [number]: () -> () } = {}
    local newDeps: { [number]: { any }? } = {}

    for i, entry in ipairs(effects) do
        local deps = entry.deps
        if deps ~= nil and prevDeps[i] ~= nil and shallowEqual(prevDeps[i] :: { any }, deps) then
            newCleanups[i] = prevCleanups[i]
            newDeps[i] = prevDeps[i]
        else
            local staleCleanup = prevCleanups[i]
            if staleCleanup then
                local ok, err = pcall(staleCleanup)
                if not ok then
                    warn(`[Fragment] "{name}": effect cleanup error — {err}`)
                end
            end

            local effOk, result = pcall(entry.fn)
            if effOk then
                if type(result) == "function" then
                    newCleanups[i] = result :: () -> ()
                end
            else
                warn(`[Fragment] "{name}": effect #{i} error — {result}`)
            end
            newDeps[i] = deps
        end
    end

    -- Fewer effects were registered this pass than last pass (a conditional
    -- Effect() call stopped firing) — tear down whatever is left over.
    for i, cleanup in pairs(prevCleanups) do
        if effects[i] == nil and newCleanups[i] == nil then
            local ok, err = pcall(cleanup)
            if not ok then
                warn(`[Fragment] "{name}": effect cleanup error — {err}`)
            end
        end
    end

    return newCleanups, newDeps
end

--[[
    Schedules exactly one deferred :Render() call for `self`, coalescing any
    number of calls made before that render actually runs into a single
    pass — mirrors React 18's automatic batching. Without this, calling two
    setters (bind, await, a store, a context) in the same tick — e.g. both
    from inside one Action — previously fired one full Render() per call.

    task.defer runs after every thread already spawned/resumed this frame
    has finished, so every setState-style call made synchronously during
    the current pass still lands before the deferred render fires.

    @param any self - A handle or ComponentInstance (anything with :Render())
]]
local function scheduleRender(self: any)
    if self._renderScheduled then return end
    self._renderScheduled = true
    task.defer(function()
        self._renderScheduled = false
        self:Render()
    end)
end

--[[
    Removes `self` from every store and context it subscribed to via
    useStore/pull. Nothing in Fragment ever called this before — handles
    were assumed to live forever — but a mounted-and-unmounted handle
    (Fragment.mount, a destroyed component instance) needs it, or it lingers
    as a dead subscriber that every future store/context update still wakes
    up and tries (harmlessly, but wastefully and permanently) to render.

    @param any self - A handle or ComponentInstance being torn down
]]
local function unsubscribeAll(self: any)
    for storeName in pairs(self._storeSubs) do
        local subs = _storeSubscribers[storeName]
        if subs then
            subs[self._id] = nil
        end
    end
    table.clear(self._storeSubs)

    for _, ctx in pairs(self._ctxSubs) do
        ctx._subscribers[self._id] = nil
    end
    table.clear(self._ctxSubs)
end

--[[
    Removes every spring owned by `self` from the shared registry — called
    when a handle/component instance is torn down so a spring mid-animation
    doesn't keep scheduling renders on something that no longer exists.

    @param any self - A handle or ComponentInstance being torn down
]]
local function removeOwnedSprings(self: any)
    for id, spring in pairs(_springs) do
        if spring.owner == self then
            _springs[id] = nil
        end
    end
end

--[[
    Advances one spring's value/velocity toward its target by `dt` seconds,
    using a damped harmonic oscillator integrated with semi-implicit Euler —
    the same model Fusion's Spring uses. `angularFreq` and `damping` come
    from handle:spring()'s frequency/damping config.

    number, Vector2 and Vector3 integrate directly (they all support scalar
    multiplication and subtraction). UDim2 has neither, so it's decomposed
    into its four plain-number components, each integrated independently,
    then recombined. Any other type (e.g. Color3, which Roblox gives no
    arithmetic operators at all) can't be integrated this way and just
    snaps straight to the target.

    @returns any, any, boolean - new value, new velocity, and whether it has settled close enough to stop
]]
local function springStep(value: any, velocity: any, target: any, angularFreq: number, damping: number, dt: number): (any, any, boolean)
    local kind = typeof(value)

    if kind == "number" then
        local accel = (target - value) * (angularFreq * angularFreq) - velocity * (2 * damping * angularFreq)
        local newVelocity = velocity + accel * dt
        local newValue = value + newVelocity * dt
        if math.abs(target - newValue) < 1e-4 and math.abs(newVelocity) < 1e-4 then
            return target, 0, true
        end
        return newValue, newVelocity, false
    elseif kind == "Vector2" or kind == "Vector3" then
        local diff: any = target - value
        local accel: any = diff * (angularFreq * angularFreq) - velocity * (2 * damping * angularFreq)
        local newVelocity: any = velocity + accel * dt
        local newValue: any = value + newVelocity * dt
        if diff.Magnitude < 1e-4 and newVelocity.Magnitude < 1e-4 then
            return target, value * 0, true
        end
        return newValue, newVelocity, false
    elseif kind == "UDim2" then
        local v: UDim2, t: UDim2, vel: UDim2 = value, target, velocity
        local xs, xsVel, xsDone = springStep(v.X.Scale, vel.X.Scale, t.X.Scale, angularFreq, damping, dt)
        local xo, xoVel, xoDone = springStep(v.X.Offset, vel.X.Offset, t.X.Offset, angularFreq, damping, dt)
        local ys, ysVel, ysDone = springStep(v.Y.Scale, vel.Y.Scale, t.Y.Scale, angularFreq, damping, dt)
        local yo, yoVel, yoDone = springStep(v.Y.Offset, vel.Y.Offset, t.Y.Offset, angularFreq, damping, dt)
        return UDim2.new(xs, xo, ys, yo), UDim2.new(xsVel, xoVel, ysVel, yoVel), xsDone and xoDone and ysDone and yoDone
    else
        return target, velocity, true
    end
end

--[[
    Steps every active spring by `dt`, schedules a render for each spring's
    owner, and prunes/disconnects once nothing is left animating. Connected
    to RunService.Heartbeat on demand by ensureSpringLoop — never runs when
    no spring is active.
]]
local function stepAllSprings(dt: number)
    dt = math.min(dt, 1 / 20) -- clamp so a lag spike can't blow up the integration

    for id, spring in pairs(_springs) do
        local slot = spring.slot
        local newValue, newVelocity, settled = springStep(slot.value, slot.velocity, slot.target, slot.angularFreq, slot.damping, dt)
        slot.value = newValue
        slot.velocity = newVelocity
        scheduleRender(spring.owner)

        if settled then
            _springs[id] = nil
        end
    end

    if next(_springs) == nil and _springHeartbeat then
        _springHeartbeat:Disconnect()
        _springHeartbeat = nil
    end
end

--[[
    Connects the shared spring-stepping Heartbeat if it isn't already
    running. Safe to call every time a spring's target changes.
]]
local function ensureSpringLoop()
    if _springHeartbeat then return end
    _springHeartbeat = RunService.Heartbeat:Connect(stepAllSprings)
end

--[[
    Creates a container for managing child instances.

    @param Instance parent - The parent instance for the container
    @returns any - Container object with child management methods
]]
local function makeContainer(parent: Instance): any
    local c: any = {
        _parent = parent,
        _children = {},
        _touchedKeys = {},
    }

    --[[
        Inserts or updates a child instance in the container.

        @param any keyOrChild - Key (string) or child instance
        @param Instance? child - Child instance (optional if first param is instance)
        @returns Instance - The existing or new child instance
    ]]
    c.UpsertChild = function(keyOrChild: any, child: Instance?): Instance
        local key: string
        local incoming: Instance

        if child ~= nil then
            key = keyOrChild :: string
            incoming = child
        else
            incoming = keyOrChild :: Instance
            key = incoming.Name
        end

        c._touchedKeys[key] = true
        local existing = c._children[key]

        if existing and existing.Parent ~= nil then
            -- If both instances have ComponentInstance contexts, re-render the
            -- surviving (existing) one with the fresh props carried by the incoming
            -- clone.  This is what gives components their own reactive lifecycle:
            -- the live instance is updated in-place rather than left stale.
            local existingCI = _componentInstances[existing]
            local incomingCI = _componentInstances[incoming]
            if existingCI and incomingCI then
                renderComponentInstance(existingCI, incomingCI._props)
            end
            incoming:Destroy()
            return existing
        else
            incoming.Parent = parent
            c._children[key] = incoming
            return incoming
        end
    end

    --[[
        Inserts a new child instance with a specific key.

        @param string key - Unique key for the child
        @param Instance child - Child instance to insert
        @returns Instance - The existing or new child instance
    ]]
    c.InsertChild = function(key: string, child: Instance): Instance
        if c._children[key] and c._children[key].Parent ~= nil then
            warn(`[Fragment] Container.InsertChild: key "{key}" already exists — use UpsertChild to overwrite`)
            child:Destroy()
            return c._children[key]
        end

        child.Parent = parent
        c._children[key] = child
        c._touchedKeys[key] = true

        return child
    end

    --[[
        Gets a child instance by key.

        @param string key - Key of the child to retrieve
        @returns Instance? - The child instance or nil if not found
    ]]
    c.GetChild = function(key: string): Instance?
        return c._children[key]
    end

    --[[
        Gets all children in the container.

        @returns { [string]: Instance } - Table of all children
    ]]
    c.GetAllChildren = function(): { [string]: Instance }
        return c._children
    end

    --[[
        Updates a child instance with a function.

        @param string key - Key of the child to update
        @param (Instance) -> () fn - Update function
    ]]
    c.UpdateChild = function(key: string, fn: (Instance) -> ())
        local child = c._children[key]

        if not child or child.Parent == nil then
            warn(`[Fragment] Container.UpdateChild: key "{key}" not found`)
            return
        end

        fn(child)
    end

    --[[
        Deletes a child instance by key.

        @param string key - Key of the child to delete
    ]]
    c.DeleteChild = function(key: string)
        local child = c._children[key]

        if child then
            child:Destroy()
            c._children[key] = nil
            c._touchedKeys[key] = nil
        end
    end

    --[[
        Clears all children from the container.
    ]]
    c.ClearChildren = function()
        for _, child in pairs(c._children) do
            child:Destroy()
        end
        table.clear(c._children)
        table.clear(c._touchedKeys)
    end

    --[[
        Renders a keyed list in one call: for each item, computes its key,
        builds its child Instance, and upserts it. This is exactly the
        UpsertChild loop every list-rendering Handle writes by hand — Each
        just removes the boilerplate. Items whose key isn't touched this
        pass are still removed at end-of-render, same as always.

        @param {any} items - Items to render, in order
        @param (item: any, index: number) -> string keyFn - Computes each item's stable key
        @param (item: any, index: number) -> Instance renderFn - Builds each item's child Instance
    ]]
    c.Each = function(items: { any }, keyFn: (item: any, index: number) -> string, renderFn: (item: any, index: number) -> Instance)
        for i, item in ipairs(items) do
            local key = keyFn(item, i)
            local child = renderFn(item, i)
            c.UpsertChild(key, child)
        end
    end

    return c
end

-- Handle methods and metatables
local HandleMethods = {}
local HandleMeta = {}

--[[
    Metamethod for calling a handle with a renderer.

    @param any self - The handle instance
    @param Renderer renderer - Render function
    @returns any - The handle instance
]]
HandleMeta.__call = function(self: any, renderer: Renderer): any
    self._renderer = renderer
    return self
end

--[[
    Metamethod for indexing handle methods.

    @param any self - The handle instance
    @param string k - Method name
    @returns any - The method or HandleMethods entry
]]
HandleMeta.__index = function(self: any, k: string): any
    local actions: { [string]: ActionFn } = rawget(self, "_actions")
    if actions then
        local fn = actions[k]
        if fn then
            return function(_self: any, ...: any): any
                return fn(...)
            end
        end
    end

    return HandleMethods[k]
end

--[[
    Resolves the handle's element path in the UI hierarchy.

    @param any self - The handle instance
    @returns boolean - True if resolution succeeded, false otherwise
]]
function HandleMethods._Resolve(self: any): boolean
    if _failedHandles[self._id] then return false end
    if self._element ~= nil then return true end

    local player = Players.LocalPlayer :: Player
    local current: Instance? = player:FindFirstChild("PlayerGui")
        or player:WaitForChild("PlayerGui")

    if not current then
        warn(`[Fragment] "{self._name}": PlayerGui not found — handle will be skipped`)
        _failedHandles[self._id] = true
        return false
    end

    for _, key in ipairs(self._path) do
        local found: Instance? = (current :: Instance):FindFirstChild(key) or (current :: Instance):WaitForChild(key)
        if not found then
            warn(`[Fragment] "{self._name}": path broken at "{key}" `
                .. `(full path: {table.concat(self._path, " → ")})`)
            _failedHandles[self._id] = true
            return false
        end
        current = found
    end

    self._element = current

    if not self._visibilityHooksConnected and self._element then
        self._visibilityHooksConnected = true
        local function onVisibilityChanged()
            -- The renderer itself may set element.Visible, which fires this
            -- signal synchronously mid-render.  Skipping re-entrant calls here
            -- prevents the double-render that causes effects to run twice.
            if self._rendering then return end
            self:Render()
        end

        local el = self._element
        table.insert(self._visibilityConnections, el:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged))
        local ancestor = el.Parent

        while ancestor and not ancestor:IsA("PlayerGui") do
            if ancestor:IsA("GuiObject") then
                table.insert(self._visibilityConnections, ancestor:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged))
            end
            if ancestor:IsA("LayerCollector") then
                table.insert(self._visibilityConnections, ancestor:GetPropertyChangedSignal("Enabled"):Connect(onVisibilityChanged))
            end
            ancestor = ancestor.Parent
        end
    end

    return true
end

--[[
    Checks if the handle's element is visible.

    @param any self - The handle instance
    @returns boolean - True if element is visible, false otherwise
]]
function HandleMethods._IsVisible(self: any): boolean
    local el: Instance? = self._element
    if not el then return false end

    if (el :: Instance):IsA("GuiObject") and not (el :: GuiObject).Visible then
        return false
    end

    local ancestor: Instance? = (el :: Instance).Parent
    while ancestor ~= nil do
        if ancestor:IsA("LayerCollector") then
            return (ancestor :: LayerCollector).Enabled
        end
        if ancestor:IsA("GuiObject") and not (ancestor :: GuiObject).Visible then
            return false
        end
        ancestor = ancestor.Parent
    end

    return true
end

--[[
    Registers actions without rendering.

    @param any self - The handle instance
]]
function HandleMethods._RegisterActionsOnly(self: any)
    if self._actionsRegistered then return end
    if not self._renderer then return end
    if not HandleMethods._Resolve(self) then return end

    self._slotIdx = 0

    rawset(self, "Action", function(actionName: string, fn: ActionFn)
        if not self._actions[actionName] then
            self._actions[actionName] = fn
        end
    end)

    local noop = function() end
    rawset(self, "Effect", noop)
    rawset(self, "Once", noop)
    rawset(self, "Connect", noop)
    rawset(self, "RegisterContainer", noop)

    local prevHandle = _activeHandle
    _activeHandle = self
    local mountOk, mountErr = pcall(self._renderer, self._element :: Instance, _data)
    _activeHandle = prevHandle

    rawset(self, "Effect", self._warnEffect)
    rawset(self, "Action", self._warnAction)
    rawset(self, "Once", self._warnOnce)
    rawset(self, "Connect", self._warnConnect)
    rawset(self, "RegisterContainer", self._warnRegisterContainer)

    self._actionsRegistered = true

    if not mountOk then
        warn(`[Fragment] "{self._name}": action-registration pass error — {mountErr}`)
    end
end

--[[
    Renders the handle and processes effects.

    Guards against re-entrancy: if something (an Action, an effect, a store
    update) calls :Render() again while this handle is already mid-render —
    e.g. a store set() triggered synchronously from inside this very render —
    that request is no longer silently dropped. It's queued and the actual
    work (_DoRender) runs again immediately after the current pass finishes,
    in a loop rather than by recursing.

    @param any self - The handle instance
]]
function HandleMethods.Render(self: any): ()
    if self._rendering then
        self._renderPending = true
        return
    end

    self._rendering = true
    repeat
        self._renderPending = false
        HandleMethods._DoRender(self)
    until not self._renderPending
    self._rendering = false
end

--[[
    Does the actual work of a single render pass. Only ever called from
    behind the re-entrancy guard in HandleMethods.Render.

    @param any self - The handle instance
]]
function HandleMethods._DoRender(self: any): ()
    if not self._renderer or not HandleMethods._Resolve(self) then
        -- Can't render right now (no renderer registered yet, or the element
        -- failed to resolve) — there's nothing to diff deps against, so tear
        -- everything down rather than leave stale effects dangling.
        for _, cleanup in pairs(self._cleanups) do
            local ok, err = pcall(cleanup)
            if not ok then
                warn(`[Fragment] "{self._name}": effect cleanup error — {err}`)
            end
        end
        table.clear(self._cleanups)
        table.clear(self._effectDeps)
        return
    end

    self._actionsRegistered = true
    self._slotIdx = 0

    local effects: { [number]: { fn: EffectFn, deps: { any }? } } = {}
    local effectIdx = 0

    rawset(self, "Effect", function(fn: EffectFn, deps: { any }?)
        effectIdx += 1
        effects[effectIdx] = { fn = fn, deps = deps }
    end)

    rawset(self, "Action", function(actionName: string, fn: ActionFn)
        if not self._actions[actionName] then
            self._actions[actionName] = fn
        end
    end)

    rawset(self, "Once", function(fn: () -> ())
        if not self._onceFired then
            self._onceFired = true
            local ok, err = pcall(fn)
            if not ok then
                warn(`[Fragment] "{self._name}": Once error — {err}`)
            end
        end
    end)

    rawset(self, "Connect", function(connName: string, signal: RBXScriptSignal, callback: (...any) -> ())
        local existing = self._connections[connName]
        if existing then
            existing:Disconnect()
        end
        self._connections[connName] = signal:Connect(callback)
    end)

    rawset(self, "RegisterContainer", function(frame: Instance): any
        if not self._containers[frame] then
            self._containers[frame] = makeContainer(frame)
        end

        local container = self._containers[frame]

        -- Queue this container for reconciliation at the END of the current
        -- render pass (after effects).  We no longer store a deferred cleanup
        -- function because that ran at the START of the NEXT render — meaning
        -- a sold/removed item would stay visible until a second render occurred.
        -- End-of-render reconciliation removes untouched children immediately,
        -- in the same frame that the renderer decided they were gone.
        table.insert(self._pendingContainers, container)

        return container
    end)

    local prevHandle = _activeHandle
    _activeHandle = self
    local rendOk, rendErr = pcall(self._renderer, self._element :: Instance, _data)
    _activeHandle = prevHandle

    rawset(self, "Effect", self._warnEffect)
    rawset(self, "Action", self._warnAction)
    rawset(self, "Once", self._warnOnce)
    rawset(self, "Connect", self._warnConnect)

    if not rendOk then
        warn(`[Fragment] "{self._name}": renderer error — {rendErr}`)
        rawset(self, "RegisterContainer", self._warnRegisterContainer)

        -- The renderer bailed before re-registering its effects: tear down
        -- whatever survived from the last successful pass rather than leak it.
        for _, cleanup in pairs(self._cleanups) do
            local ok, err = pcall(cleanup)
            if not ok then
                warn(`[Fragment] "{self._name}": effect cleanup error — {err}`)
            end
        end
        table.clear(self._cleanups)
        table.clear(self._effectDeps)
        return
    end

    local prevHandle2 = _activeHandle
    _activeHandle = self
    self._cleanups, self._effectDeps = runEffects(self._name, effects, self._cleanups, self._effectDeps)
    _activeHandle = prevHandle2

    rawset(self, "RegisterContainer", self._warnRegisterContainer)

    -- Reconcile all containers that were registered during this render pass.
    -- Any child whose key was not touched (i.e. not present in the new data)
    -- is destroyed immediately — same frame, same render — rather than waiting
    -- until the start of the next render where a second store change would be
    -- required to trigger it.
    for _, container in ipairs(self._pendingContainers) do
        for key, child in pairs(container._children) do
            if not container._touchedKeys[key] then
                child:Destroy()
                container._children[key] = nil
            end
        end
        table.clear(container._touchedKeys)
    end
    table.clear(self._pendingContainers)
end

--[[
    Disconnects a named connection.

    @param any self - The handle instance
    @param string connName - Name of the connection to disconnect
]]
function HandleMethods.Disconnect(self: any, connName: string): ()
    local conn = self._connections[connName]
    if conn then
        conn:Disconnect()
        self._connections[connName] = nil
    else
        warn(`[Fragment] "{self._name}": Disconnect — no connection named "{connName}"`)
    end
end

--[[
    Tears a handle down for good: runs every effect cleanup, disconnects
    every Connect()/visibility/attribute connection, removes it from every
    store and context it subscribed to, and cancels any spring still
    animating on it. Idempotent — safe to call more than once.

    newHandle-created handles are meant to live for the whole session and
    never need this. It exists for handles that come and go on their own —
    Fragment.mount is the main one (a Storybook/Flipbook/UI Labs preview,
    anything mounted into a container that isn't a permanent screen).

    @param any self - The handle instance
]]
function HandleMethods.Unmount(self: any): ()
    if self._unmounted then return end
    self._unmounted = true
    _failedHandles[self._id] = true -- belt-and-suspenders: any render that slips through becomes a safe no-op

    for _, cleanup in pairs(self._cleanups) do
        pcall(cleanup)
    end
    table.clear(self._cleanups)

    for _, conn in pairs(self._connections) do
        conn:Disconnect()
    end
    table.clear(self._connections)

    for _, conn in ipairs(self._visibilityConnections) do
        conn:Disconnect()
    end
    table.clear(self._visibilityConnections)

    for _, conn in ipairs(self._attributeConnections) do
        conn:Disconnect()
    end
    table.clear(self._attributeConnections)

    unsubscribeAll(self)
    removeOwnedSprings(self)
end

--[[
    Creates a reactive state binding.

    @param any self - The handle instance
    @param any initialValue - Initial value
    @returns (()->any, (any)->()) - Getter and setter functions
]]
function HandleMethods.bind(self: any, initialValue: any): (()->any, (any)->())
    if _activeHandle ~= self then
        warn(`[Fragment] "{self._name}": handle:bind() must be called inside a renderer.`)
        local v = initialValue
        return function() return v end, function(_: any) end
    end

    self._slotIdx += 1
    local idx = self._slotIdx

    if self._slots[idx] == nil then
        local slot: any = { value = initialValue }

        -- Getter
        slot.getter = function(): any
            return slot.value
        end

        -- Setter
        slot.setter = function(newValue: any)
            if slot.value == newValue then return end
            slot.value = newValue
            scheduleRender(self)
        end

        self._slots[idx] = slot
    end

    local slot = self._slots[idx]
    return slot.getter, slot.setter
end

--[[
    Creates a value that animates toward whatever target the setter is given
    using damped spring physics, instead of jumping straight there — the
    same idea as Fusion's Spring. The returned getter keeps changing on its
    own (via a shared RunService.Heartbeat) until the value settles close
    enough to the target; each step schedules a render the same way bind's
    setter does, so reading the getter in the renderer just works.

    Supports number, Vector2, Vector3 and UDim2. Any other type (Color3 has
    no arithmetic in Roblox, for instance) can't be integrated and snaps
    straight to the target — see springStep.

    @param any self - The handle instance
    @param any initialValue - Starting value — also fixes the type every future target must match
    @param { frequency: number?, damping: number? }? config - frequency: oscillations/sec if undamped (default 4); damping: 1 = critically damped, <1 = bouncy, >1 = sluggish (default 1)
    @returns () -> any, (any) -> () - getter for the current (animating) value, setter for a new target
]]
function HandleMethods.spring(self: any, initialValue: any, config: { frequency: number?, damping: number? }?): (() -> any, (any) -> ())
    if _activeHandle ~= self then
        warn(`[Fragment] "{self._name}": handle:spring() must be called inside a renderer.`)
        local v = initialValue
        return function() return v end, function(_: any) end
    end

    self._slotIdx += 1
    local idx = self._slotIdx

    if self._slots[idx] == nil then
        local kind = typeof(initialValue)
        local zeroVelocity: any
        if kind == "number" then
            zeroVelocity = 0
        elseif kind == "Vector2" then
            zeroVelocity = Vector2.zero
        elseif kind == "Vector3" then
            zeroVelocity = Vector3.zero
        elseif kind == "UDim2" then
            zeroVelocity = UDim2.new()
        else
            zeroVelocity = initialValue
        end

        local slot: any = {
            value = initialValue,
            velocity = zeroVelocity,
            target = initialValue,
            angularFreq = ((config and config.frequency) or 4) * 2 * math.pi,
            damping = (config and config.damping) or 1,
        }

        slot.getter = function(): any
            return slot.value
        end

        slot.setter = function(newTarget: any)
            if slot.target == newTarget then return end
            slot.target = newTarget
            _springs[`Spring_{self._id}_{idx}`] = { slot = slot, owner = self }
            ensureSpringLoop()
        end

        self._slots[idx] = slot
    end

    local slot = self._slots[idx]
    return slot.getter, slot.setter
end

--[[
    Creates a derived value that updates when dependencies change.

    @param any self - The handle instance
    @param () -> any fn - Derivation function
    @param {any} deps - Dependency values
    @returns () -> any - Function that returns the derived value
]]
function HandleMethods.derive(self: any, fn: () -> any, deps: { any }): () -> any
	if _activeHandle ~= self then
		warn(`[Fragment] "{self._name}": handle:derive() must be called inside a renderer.`)
		return function() end
	end

	self._slotIdx += 1
	local idx = self._slotIdx

	if self._slots[idx] == nil then
		self._slots[idx] = { value = UNSET, deps = nil }
	end

	local slot = self._slots[idx]

	return function(): any
		if slot.value == UNSET or not shallowEqual(slot.deps, deps) then
			local ok, result = pcall(fn)
			if not ok then
				warn(`[Fragment] "{self._name}": derive computation error — {result}`)
				result = nil
			end

			slot.value = result
			slot.deps = deps
		end

		return slot.value
	end
end

--[[
    Memoizes a function based on dependencies.

    @param any self - The handle instance
    @param (...any) -> any fn - Function to memoize
    @param {any} deps - Dependency values
    @returns (...any) -> any - Memoized function
]]
function HandleMethods.hold(self: any, fn: (...any) -> any, deps: { any }): (...any) -> any
    if _activeHandle ~= self then
        warn(`[Fragment] "{self._name}": handle:hold() must be called inside a renderer.`)
        return fn
    end

    self._slotIdx += 1
    local idx = self._slotIdx

    if self._slots[idx] == nil then
        self._slots[idx] = { fn = fn, deps = nil }
    end

    local slot = self._slots[idx]
    if not shallowEqual(slot.deps, deps) then
        slot.fn = fn
        slot.deps = deps
    end

    return slot.fn
end

--[[
    Handles asynchronous operations with loading states.

    @param any self - The handle instance
    @param () -> any fn - Async function
    @param {any}? deps - Dependency values (optional)
    @returns { status: string, value: any, error: any } - Async operation state
]]
function HandleMethods.await(self: any, fn: () -> any, deps: { any }?): { status: string, value: any, error: any }
    if _activeHandle ~= self then
        warn(`[Fragment] "{self._name}": handle:await() must be called inside a renderer.`)
        return { status = "rejected", value = nil, error = "called outside renderer" }
    end

    self._slotIdx += 1
    local idx = self._slotIdx

    --[[
        Executes an async function and updates the slot state.

        @param any slot - The slot containing async state
    ]]
    local function run(slot: any)
        slot.status = "pending"
        slot.value = nil
        slot.error = nil
        task.spawn(function()
            local ok, result = pcall(fn)
            if ok then
                slot.status = "resolved"
                slot.value = result
            else
                slot.status = "rejected"
                slot.error = result
            end
            scheduleRender(self)
        end)
    end

    if self._slots[idx] == nil then
        local slot = { status = "pending", value = nil, error = nil, deps = UNSET }

        self._slots[idx] = slot
        run(slot)
    else
        local slot = self._slots[idx]

        if deps ~= nil and not shallowEqual(slot.deps, deps) then
            slot.deps = deps
            run(slot)
        end
    end

    return self._slots[idx]
end

--[[
    Pulls value from a context.

    @param any self - The handle instance
    @param any ctx - Context object
    @returns any - Context value
]]
function HandleMethods.pull(self: any, ctx: any): any
    if _activeHandle ~= self then
        warn(`[Fragment] "{self._name}": handle:pull() must be called inside a renderer.`)
        return ctx._value
    end

    if not self._ctxSubs[ctx._id] then
        self._ctxSubs[ctx._id] = ctx
        ctx._subscribers[self._id] = self
    end

    return ctx._value
end

--[[
    Subscribes to a replicated Instance Attribute and returns a getter for
    its current value. Whatever sets it — a server script via
    instance:SetAttribute(name, value), ReplicaService, Knit, a plain
    RemoteEvent handler, anything — shows up here reactively, through
    Roblox's own attribute replication, without Fragment depending on any
    particular networking library. This is Fragment's "replicated store":
    lighter than wiring up a full store by hand for values the engine
    already syncs for you.

    Like bind, the (instance, attributeName) pair is fixed on first call for
    this slot — calling it again with a different instance/name on a later
    render does not re-subscribe.

    @param any self - The handle instance
    @param Instance instance - The Instance whose attribute is being watched
    @param string attributeName - The attribute's name
    @returns () -> any - Getter for the attribute's current value
]]
function HandleMethods.attribute(self: any, instance: Instance, attributeName: string): () -> any
    if _activeHandle ~= self then
        warn(`[Fragment] "{self._name}": handle:attribute() must be called inside a renderer.`)
        return function(): any return instance:GetAttribute(attributeName) end
    end

    self._slotIdx += 1
    local idx = self._slotIdx

    if self._slots[idx] == nil then
        local slot: any = { value = instance:GetAttribute(attributeName) }

        local conn = instance:GetAttributeChangedSignal(attributeName):Connect(function()
            slot.value = instance:GetAttribute(attributeName)
            scheduleRender(self)
        end)
        table.insert(self._attributeConnections, conn)

        self._slots[idx] = slot
    end

    local slot = self._slots[idx]
    return function(): any
        return slot.value
    end
end

-- ─── Component Instance Lifecycle ────────────────────────────────────────────
--
-- A ComponentInstance (CI) is a lightweight, self-contained lifecycle context
-- owned by a single live component instance (a parented clone).  It mirrors the
-- handle API — Effect, Connect, Once, RegisterContainer, bind, derive, hold,
-- await, pull — but is scoped entirely to one UI instance rather than a whole
-- screen handle.
--
-- Lifecycle:
--   mount   — CI is created and its renderer runs the first time the clone is
--             inserted into a container via UpsertChild / InsertChild.
--   update  — UpsertChild receives a new clone for an existing key; instead of
--             returning the stale existing instance, it re-runs the CI's renderer
--             with the new props (running cleanup first, then fresh effects).
--   unmount — instance.Destroying fires (triggered by DeleteChild, ClearChildren,
--             or any explicit :Destroy call), running all cleanups and disconnecting
--             all connections.  The CI entry is removed from _componentInstances.
--
-- bind/derive/hold/await/pull are shared directly from HandleMethods because
-- they are generic: they only access self._slots, self._slotIdx, self._id,
-- self._name, self._ctxSubs, and call self:Render() — all present on a CI.

local ComponentInstanceMethods = {}
local ComponentInstanceMeta    = { __index = ComponentInstanceMethods }

-- Reuse handle slot/context hooks verbatim — they work on any object that
-- exposes the same fields and a :Render() method.
ComponentInstanceMethods.bind      = HandleMethods.bind
ComponentInstanceMethods.derive    = HandleMethods.derive
ComponentInstanceMethods.hold      = HandleMethods.hold
ComponentInstanceMethods.await     = HandleMethods.await
ComponentInstanceMethods.pull      = HandleMethods.pull
ComponentInstanceMethods.spring    = HandleMethods.spring
ComponentInstanceMethods.attribute = HandleMethods.attribute

--[[
    Re-renders this component instance with its last-known props.
    Called by bind/await setters when reactive state changes.

    Guarded the same way as HandleMethods.Render: a :Render() call that
    arrives while this instance is already mid-render is queued instead of
    silently dropped, and runs right after the current pass finishes.
]]
function ComponentInstanceMethods.Render(self: any)
    if self._rendering then
        self._renderPending = true
        return
    end

    self._rendering = true
    repeat
        self._renderPending = false
        renderComponentInstance(self, self._props)
    until not self._renderPending
    self._rendering = false
end

--[[
    Creates a ComponentInstance for the given live instance.

    Sets up warn stubs for all lifecycle methods (swapped out for real
    implementations during a render pass), and registers a Destroying
    listener for guaranteed cleanup when the instance leaves the DataModel.

    @param string   componentName - Name of the component definition
    @param Instance instance      - The live (parented or soon-to-be-parented) clone
    @returns any - The new ComponentInstance
]]
local function createComponentInstance(componentName: string, instance: Instance): any
    _componentInstanceCount += 1

    local ci: any = setmetatable({
        _id            = `ComponentInstance_{_componentInstanceCount}`,
        _name          = componentName,   -- used by shared HandleMethods warn strings
        _componentName = componentName,
        _instance      = instance,
        _props         = {},
        _effectDeps    = {},
        _cleanups      = {},
        _connections   = {},
        _containers    = {},
        _pendingContainers = {},
        _slots         = {},
        _slotIdx       = 0,
        _onceFired     = false,
        _ctxSubs       = {},
        _storeSubs     = {},
        _attributeConnections = {},
        _rendering       = false,
        _renderPending   = false,
        _renderScheduled = false,
    }, ComponentInstanceMeta)

    -- Warn stubs — active outside of a render pass so accidental calls are caught.
    ci._warnEffect            = function() warn(`[Fragment] Component "{componentName}" instance: Effect called outside a renderer — ignored.`) end
    ci._warnConnect           = function() warn(`[Fragment] Component "{componentName}" instance: Connect called outside a renderer — ignored.`) end
    ci._warnOnce              = function() warn(`[Fragment] Component "{componentName}" instance: Once called outside a renderer — ignored.`) end
    ci._warnRegisterContainer = function() warn(`[Fragment] Component "{componentName}" instance: RegisterContainer called outside a renderer — ignored.`) end

    ci.Effect            = ci._warnEffect
    ci.Connect           = ci._warnConnect
    ci.Once              = ci._warnOnce
    ci.RegisterContainer = ci._warnRegisterContainer

    -- Guaranteed unmount: fires on :Destroy(), DeleteChild, ClearChildren, or any
    -- external destruction.  Runs all effect cleanups, disconnects every
    -- connection, and — same reasoning as HandleMethods.Unmount — removes
    -- this CI from every store/context/spring it joined via useStore/pull/
    -- spring, so a destroyed list item doesn't linger as a dead subscriber.
    instance.Destroying:Connect(function()
        _componentInstances[instance] = nil

        for _, cleanup in pairs(ci._cleanups) do
            pcall(cleanup)
        end
        table.clear(ci._cleanups)

        for _, conn in pairs(ci._connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(ci._connections)

        for _, conn in ipairs(ci._attributeConnections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(ci._attributeConnections)

        unsubscribeAll(ci)
        removeOwnedSprings(ci)
    end)

    _componentInstances[instance] = ci
    return ci
end

--[[
    Runs a full render pass on a ComponentInstance.

    Order of operations mirrors HandleMethods._DoRender:
      1. Disconnect connections from the previous pass (Connect has no deps
         array, so it always tears down and reconnects fresh).
      2. Reset slot index (bind/derive/hold slots are positional).
      3. Store incoming props on the CI for reactive re-renders (bind/await).
      4. Activate lifecycle methods (Effect, Connect, Once, RegisterContainer).
      5. Set _activeHandle = ci so Fragment.compose / useStore / useComponent
         all work correctly inside the component renderer.
      6. Call component._renderer(instance, props, ci).
      7. Restore _activeHandle and deactivate lifecycle methods back to warn stubs.
      8. Diff this pass' effects against the last pass' (runEffects), skipping
         teardown/rerun for any whose deps are unchanged.

    @param any                  ci    - The ComponentInstance to render
    @param { [string]: any }    props - Props to pass to the renderer
]]
renderComponentInstance = function(ci: any, props: { [string]: any })
    -- 1. Connections have no dependency array — always disconnect and let the
    --    renderer reconnect fresh, same as every past render.
    for _, conn in pairs(ci._connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(ci._connections)

    -- 2. Reset slot index so bind/derive/hold slots line up correctly
    ci._slotIdx = 0

    -- 3. Store props for reactive re-renders triggered by bind/await
    ci._props = props

    -- 4. Collect effects during this pass
    local effects: { [number]: { fn: EffectFn, deps: { any }? } } = {}
    local effectIdx = 0

    rawset(ci, "Effect", function(fn: EffectFn, deps: { any }?)
        effectIdx += 1
        effects[effectIdx] = { fn = fn, deps = deps }
    end)

    rawset(ci, "Connect", function(connName: string, signal: RBXScriptSignal, callback: (...any) -> ())
        local existing = ci._connections[connName]
        if existing then existing:Disconnect() end
        ci._connections[connName] = signal:Connect(callback)
    end)

    rawset(ci, "Once", function(fn: () -> ())
        if not ci._onceFired then
            ci._onceFired = true
            local ok, err = pcall(fn)
            if not ok then
                warn(`[Fragment] Component "{ci._componentName}" instance: Once error — {err}`)
            end
        end
    end)

    rawset(ci, "RegisterContainer", function(frame: Instance): any
        if not ci._containers[frame] then
            ci._containers[frame] = makeContainer(frame)
        end
        local container = ci._containers[frame]
        table.insert(ci._pendingContainers, container)
        return container
    end)

    -- 5 & 6. Run renderer with _activeHandle set to this CI so all
    --        Fragment.compose hooks (useHoverScale, useStore, etc.) bind to it.
    local component = _components[ci._componentName]
    local prevHandle = _activeHandle
    _activeHandle = ci
    local rendOk, rendErr = pcall(component._renderer, ci._instance, props, ci)
    _activeHandle = prevHandle

    -- 7. Swap lifecycle methods back to warn stubs
    rawset(ci, "Effect",            ci._warnEffect)
    rawset(ci, "Connect",           ci._warnConnect)
    rawset(ci, "Once",              ci._warnOnce)
    rawset(ci, "RegisterContainer", ci._warnRegisterContainer)

    if not rendOk then
        warn(`[Fragment] Component "{ci._componentName}" instance: renderer error — {rendErr}`)

        -- The renderer bailed before re-registering its effects: tear down
        -- whatever survived from the last successful pass rather than leak it.
        for _, cleanup in pairs(ci._cleanups) do
            pcall(cleanup)
        end
        table.clear(ci._cleanups)
        table.clear(ci._effectDeps)
        table.clear(ci._pendingContainers)
        return
    end

    -- 8. Diff this pass' effects against the previous pass'
    local prevHandle2 = _activeHandle
    _activeHandle = ci
    ci._cleanups, ci._effectDeps = runEffects(ci._name, effects, ci._cleanups, ci._effectDeps)
    _activeHandle = prevHandle2

    -- 9. Reconcile component-owned containers (same end-of-render logic as handles)
    for _, container in ipairs(ci._pendingContainers) do
        for key, child in pairs(container._children) do
            if not container._touchedKeys[key] then
                child:Destroy()
                container._children[key] = nil
            end
        end
        table.clear(container._touchedKeys)
    end
    table.clear(ci._pendingContainers)
end

-- ─────────────────────────────────────────────────────────────────────────────

-- Fragment module definition
local Fragment = {}

--[[
    Creates a new data store.

    @param string name - Store name
    @param (set: (any) -> (), get: () -> any) -> any builder - Store builder function
    @returns any - The created store
]]
function Fragment.createStore(name: string, builder: (set: (any) -> (), get: () -> any) -> any): any
    if _stores[name] then
        warn(`[Fragment] createStore: Store "{name}" is already registered.`)
        return _stores[name]
    end

    _storeSubscribers[name] = {}
    local store = {}

    --[[
        Gets the current store value.

        @returns any - The store's data table
    ]]
    local function get(): any
        return store
    end

    --[[
        Updates the store with new data and notifies subscribers.

        @param any partial - Partial data to update
    ]]
    local function set(partial: any): any
        local changed = false
        if type(partial) == "table" then
            for k, v in pairs(partial) do
                if store[k] ~= v then
                    store[k] = v
                    changed = true
                end
            end
        end
        if changed then
            for _, handle in pairs(_storeSubscribers[name]) do
                scheduleRender(handle)
            end
        end
    end

    local initialState = builder(set, get)
    for k, v in pairs(initialState) do
        store[k] = v
    end

    _stores[name] = store
    return store
end

--[[
    Gets a store by name and subscribes the current handle.

    @param string name - Store name
    @returns any - The store or nil if not found
]]
function Fragment.useStore(name: string): any
    local store = _stores[name]
    if not store then
        warn(`[Fragment] useStore: Store "{name}" not found.`)
        return nil
    end

    if _activeHandle then
        _storeSubscribers[name][_activeHandle._id] = _activeHandle
        _activeHandle._storeSubs[name] = true
    end

    return store
end

--[[
    Creates a new context.

    @param { [string]: any } defaults - Default context values
    @returns any - Context object with patch method
]]
function Fragment.createContext(defaults: { [string]: any }): any
    _contextCount += 1
    local ctx: any = {
        _id = `Context_{_contextCount}`,
        _value = {},
        _subscribers = {},
    }

    for k, v in pairs(defaults) do
        ctx._value[k] = v
    end

    --[[
        Updates context values and notifies subscribers.

        @param any self - The context instance
        @param { [string]: any } partial - Partial values to update
    ]]
    ctx.patch = function(self: any, partial: { [string]: any })
        for k, v in pairs(partial) do
            if v == Fragment.DELETE then
                self._value[k] = nil
            else
                self._value[k] = v
            end
        end

        for _, handle in pairs(self._subscribers) do
            scheduleRender(handle)
        end
    end

    return ctx
end

--[[
    Creates a composable binding function.

    @param (handle: any, ...any) -> any fn - Binding function
    @returns (...any) -> any - Composed function
]]
function Fragment.compose(fn: (handle: any, ...any) -> any): (...any) -> any
    return function(...)
        if _activeHandle == nil then
            warn("[Fragment] compose: composite binding called outside a renderer — ignored.")
            return nil
        end

        return fn(_activeHandle, ...)
    end
end

-- Sentinel key for Fragment.create's `props` table: `[Fragment.Children] = ...`
-- names the children to parent under the new Instance, same convention
-- Fusion uses. A fresh, opaque table rather than a string so it can never
-- collide with a real property name.
Fragment.Children = {}

--[[
    Builds a sentinel key for Fragment.create's `props` table:
    `[Fragment.OnEvent("Activated")] = fn` connects fn to element.Activated
    as part of construction, instead of needing a separate :Connect call
    after the fact.

    @param string eventName - Name of the event to connect (e.g. "Activated", "MouseButton1Click")
    @returns any - An opaque key, valid as a `props` entry for exactly this one call
]]
function Fragment.OnEvent(eventName: string): any
    return { __fragmentEvent = eventName }
end

--[[
    Builds a Roblox Instance from code — no Studio template required. This
    is Fragment's answer to Roact.createElement / Fusion.New: instead of
    resolving a hand-placed template by path, it creates the Instance right
    now, applies every property in `props`, connects any `[OnEvent(...)]`
    handlers, and parents the given `[Children]` under it.

    Unlike a virtual-DOM library's createElement, this is eager — it
    returns a real, already-configured Instance immediately, not a
    description of one to be reconciled later. That fits how Fragment
    already works: renderers re-run imperatively, and lists are reconciled
    by key via Container.UpsertChild/Each, not by diffing a tree.

    [Children] is always a table of Instances — `{ label }` for one
    anonymous child, `{ Title = label }` to also rename it, or a mix of
    both for several. There's no bare-Instance shortcut: wrapping in `{}`
    is one character and keeps this one unambiguous shape instead of two.

    @param string className - Instance.new's class name
    @param { [any]: any }? props - Properties to set, plus optional [Fragment.Children] and [Fragment.OnEvent(...)] entries
    @returns Instance - The newly created, fully configured Instance
]]
function Fragment.create(className: string, props: { [any]: any }?): Instance
    local inst = Instance.new(className)

    if props then
        local children: { [any]: Instance }? = nil

        for key, value in pairs(props) do
            if key == Fragment.Children then
                children = value
            elseif type(key) == "table" and key.__fragmentEvent then
                (inst :: any)[key.__fragmentEvent]:Connect(value)
            elseif type(key) == "string" then
                (inst :: any)[key] = value
            end
        end

        if children then
            for childKey, child in pairs(children) do
                if type(childKey) == "string" then
                    child.Name = childKey
                end
                child.Parent = inst
            end
        end
    end

    return inst
end

--[[
    Builds a bare handle table, shared by newHandle (path-resolved, added to
    the global registry) and mount (element given directly, never
    registered). Everything past construction — warn stubs, slots,
    subscription tracking — is identical either way.

    @param string name - Handle name, for warnings
    @param {string}? path - Path under PlayerGui to resolve, or nil for a handle whose _element is set directly (mount)
    @returns any - The new handle, not yet registered anywhere
]]
local function makeHandle(name: string, path: { string }?): any
    _handleCount += 1

    local handle: any = setmetatable({
        _id = `Handle_{_handleCount}`,
        _name = name,
        _path = path,
        _element = nil   :: Instance?,
        _renderer = nil   :: Renderer?,
        _effectDeps = {}    :: { [number]: { any }? },
        _cleanups = {}    :: { [number]: () -> () },
        _actions = {}    :: { [string]: ActionFn },
        _onceFired = false,
        _actionsRegistered = false,
        _connections = {},
        _containers = {},
        _pendingContainers = {},
        _states = {},
        _slots = {},
        _slotIdx = 0,
        _ctxSubs = {},
        _storeSubs = {},
        _attributeConnections = {},
        _visibilityHooksConnected = false,
        _visibilityConnections = {},
        _rendering = false,
        _renderPending = false,
        _renderScheduled = false,
        _unmounted = false,

        _warnEffect = nil,
        _warnAction = nil,
        _warnOnce = nil,
        _warnConnect = nil,
        _warnRegisterContainer = nil,
        Effect = nil,
        Action = nil,
        Once = nil,
        Connect = nil,
        RegisterContainer = nil,
    }, HandleMeta)

    handle._warnEffect = function() warn(`[Fragment] "{name}": Handle.Effect called outside a renderer — ignored.`) end
    handle._warnAction = function() warn(`[Fragment] "{name}": Handle.Action called outside a renderer — ignored.`) end
    handle._warnOnce = function() warn(`[Fragment] "{name}": Handle.Once called outside a renderer — ignored.`) end
    handle._warnConnect = function() warn(`[Fragment] "{name}": Handle.Connect called outside a renderer — ignored.`) end
    handle._warnRegisterContainer = function() warn(`[Fragment] "{name}": Handle.RegisterContainer called outside a renderer — ignored.`) end

    handle.Effect = handle._warnEffect
    handle.Action = handle._warnAction
    handle.Once = handle._warnOnce
    handle.Connect = handle._warnConnect
    handle.RegisterContainer = handle._warnRegisterContainer

    return handle
end

--[[
    Creates a new handle for managing UI elements.

    @param string name - Handle name
    @param {string} path - Path to the UI element
    @returns any - The created handle
]]
function Fragment.newHandle(name: string, path: { string }): any
    if _registry[name] then
        warn(`[Fragment] newHandle: "{name}" is already registered — it will be overwritten`)
    end

    local handle = makeHandle(name, path)
    _registry[name] = handle
    return handle
end

--[[
    Mounts `renderer` directly onto an already-existing Instance, bypassing
    the PlayerGui path-resolution newHandle relies on. For anything that
    isn't a permanent screen reached by a fixed path: a Storybook/Flipbook/
    UI Labs preview target, a tooltip parented wherever the cursor currently
    is, anything built and torn down on the fly rather than living for the
    whole session.

    Unlike newHandle, a mounted handle is never added to the global registry
    — dispatchAll/getHandle never see it, since it has no stable name and is
    expected to come and go. It renders once immediately; call :Render()
    again yourself if you need to. Call :Unmount() when you're done with it
    — see HandleMethods.Unmount for exactly what that tears down.

    @param Instance container - Already-existing Instance to render into
    @param Renderer renderer - Render function, same signature as Handle(fn)
    @returns any - A handle-like object — :Render() and :Unmount() both work on it
]]
function Fragment.mount(container: Instance, renderer: Renderer): any
    _mountCount += 1

    local handle = makeHandle(`Mount_{_mountCount}`, nil)
    handle._element = container
    handle._renderer = renderer
    handle:Render()

    return handle
end

--[[
    Gets a handle by name.

    @param string name - Handle name
    @returns any - The handle or nil if not found
]]
function Fragment.getHandle(name: string): any
    local handle = _registry[name]
    if not handle then
        warn(`[Fragment] getHandle: no handle named "{name}" is registered`)
        return nil
    end

    return handle
end

--[[
    Renders all handles.
]]
function Fragment.dispatchAll(): ()
    for _, handle in pairs(_registry) do
        handle:Render()
    end
end

--[[
    Loads and initializes all Fragment modules.

    Accepts either a single folder (legacy) or a structured table of folders.

    Legacy usage — retro-compatible, unchanged behaviour:
        Fragment.load(script.Parent.Handles)

    Structured usage — loads in guaranteed dependency order with no race conditions:
        Fragment.load({
            Stores     = script.Parent.Stores,
            Contexts   = script.Parent.Contexts,
            Hooks      = script.Parent.Hooks,
            Components = script.Parent.Components,
            Handles    = script.Parent.Handles,
        })

    All keys are optional. When using the structured form, folders are required
    in the order listed above so every dependency is registered before anything
    that references it is loaded. Handles are always last.

    @param Instance | { Stores: Instance?, Contexts: Instance?, Hooks: Instance?, Components: Instance?, Handles: Instance? } target
]]
function Fragment.load(target: Instance | { [string]: Instance }): ()
    local function requireFolder(f: Instance)
        if not f then return end
        for _, child in ipairs(f:GetChildren()) do
            if child:IsA("ModuleScript") then
                local ok, result = pcall(require, child :: ModuleScript)
                if not ok then
                    warn(`[Fragment] load: failed to require "{child.Name}" — {result}`)
                end
            elseif child:IsA("Folder") then
                requireFolder(child)
            end
        end
    end

    if typeof(target) == "Instance" then
        requireFolder(target)
    else
        local ordered = { "Stores", "Contexts", "Hooks", "Components", "Handles" }
        for _, key in ipairs(ordered) do
            requireFolder((target :: any)[key])
        end
    end

    for _, handle in pairs(_registry) do
        handle:_RegisterActionsOnly()
    end

    Fragment.dispatchAll()
end

--[[
    Creates and plays a tween animation.
    Added this because why not honestly and it lowkey helps a lot as well.

    @param Instance element - Element to animate
    @param number duration - Animation duration
    @param { [string]: any } props - Properties to animate
    @param Enum.EasingStyle? style - Easing style (optional)
    @param Enum.EasingDirection? direction - Easing direction (optional)
    @returns Tween - The created tween
]]
function Fragment.tween(
    element:   Instance,
    duration:  number,
    props:     { [string]: any },
    style:     Enum.EasingStyle?,
    direction: Enum.EasingDirection?
): Tween
    local info = TweenInfo.new(
        duration,
        style     or Enum.EasingStyle.Quad,
        direction or Enum.EasingDirection.InOut
    )
    local tween = TweenService:Create(element :: any, info, props)
    tween:Play()
    return tween
end

local ComponentMeta = {}

ComponentMeta.__call = function(self: any, renderer: (element: Instance, props: { [string]: any }, handle: any) -> ()): any
    self._renderer = renderer
    return self
end

ComponentMeta.__index = ComponentMeta

--[[
    Creates a new reusable component definition.

    Component renderers receive three arguments:
      element — the cloned template instance
      props   — the props table passed to useComponent
      handle  — the calling handle, giving the component full access to
                Effect, Action, Once, Connect, RegisterContainer, bind,
                derive, hold, pull, useStore, and all Fragment hooks

    The path resolves from the DataModel root (game), not PlayerGui, since
    components are typically templates stored in assets folders.

    @param string   name - Unique component name
    @param {string} path - Path from game root to the template instance
    @returns any - The component definition; call it with a renderer to complete registration
]]
function Fragment.newComponent(name: string, path: { string }): any
    if _components[name] then
        warn(`[Fragment] newComponent: "{name}" is already registered — it will be overwritten`)
    end

    local component: any = setmetatable({
        _name     = name,
        _path     = path,
        _renderer = nil,
    }, ComponentMeta)

    _components[name] = component
    return component
end

--[[
    Clones the template for a registered component, creates a ComponentInstance
    that owns the clone's full lifecycle, runs the component renderer through
    that CI, and returns the clone unparented.

    When the clone is subsequently passed to a container method (UpsertChild /
    InsertChild), the container transfers or re-uses the ComponentInstance:

      • First insertion — the CI is already attached; the clone is parented and
        its Destroying listener guarantees cleanup on removal.

      • Subsequent renders (UpsertChild, existing key) — the container re-renders
        the EXISTING instance's CI with the fresh props carried by the new clone,
        then destroys the clone (which cleans up its own transient CI via Destroying).

    This means all Effect, Connect, Once, bind, derive, hold, await, pull calls
    inside a component renderer are scoped to that specific instance — not
    delegated to the calling handle — and the component re-renders itself
    cleanly on every parent render pass without leaking connections or effects.

    @param string            name  - Component name as passed to newComponent
    @param { [string]: any } props - Props table forwarded to the component renderer
    @returns Instance? - The cloned and rendered instance, or nil on failure
]]
function Fragment.useComponent(name: string, props: { [string]: any }): Instance?
    if not _activeHandle then
        warn(`[Fragment] Component "{name}": called outside a renderer — ignored.`)
        return nil
    end

    local component = _components[name]
    if not component then
        warn(`[Fragment] useComponent: no component named "{name}" is registered`)
        return nil
    end

    if not component._renderer then
        warn(`[Fragment] useComponent: component "{name}" has no renderer`)
        return nil
    end

    local current: Instance = game
    for _, key in ipairs(component._path) do
        local found = current:FindFirstChild(key)
        if not found then
            warn(`[Fragment] useComponent: "{name}": path broken at "{key}" (full path: {table.concat(component._path, " → ")})`)
            return nil
        end
        current = found
    end

    local clone = current:Clone()

    local ci = createComponentInstance(name, clone)
    renderComponentInstance(ci, props or {})

    return clone
end

-- Sentinel marker
Fragment.DELETE = {}

return Fragment