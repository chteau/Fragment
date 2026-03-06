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

    @param any self - The handle instance
]]
function HandleMethods.Render(self: any): ()
    if self._rendering then return end
    self._rendering = true

    for _, cleanup in pairs(self._cleanups) do
        local ok, err = pcall(cleanup)
        if not ok then
            warn(`[Fragment] "{self._name}": effect cleanup error — {err}`)
        end
    end
    table.clear(self._cleanups)

    if not self._renderer then return end
    if not HandleMethods._Resolve(self) then return end

    self._actionsRegistered = true
    self._slotIdx = 0

    table.clear(self._effects)
    local effectIdx = 0

    rawset(self, "Effect", function(fn: EffectFn)
        effectIdx += 1
        self._effects[effectIdx] = fn
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
        self._rendering = false
        return
    end

    local prevHandle2 = _activeHandle
    _activeHandle = self
    for i, effectFn in ipairs(self._effects) do
        local effOk, result = pcall(effectFn)

        if effOk then
            if type(result) == "function" then
                self._cleanups[i] = result :: () -> ()
            end
        else
            warn(`[Fragment] "{self._name}": effect #{i} error — {result}`)
        end
    end
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

    self._rendering = false
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
            task.spawn(function() self:Render() end)
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
            task.spawn(function() self:Render() end)
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
        self._ctxSubs[ctx._id] = true
        ctx._subscribers[self._id] = self
    end

    return ctx._value
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
ComponentInstanceMethods.bind   = HandleMethods.bind
ComponentInstanceMethods.derive = HandleMethods.derive
ComponentInstanceMethods.hold   = HandleMethods.hold
ComponentInstanceMethods.await  = HandleMethods.await
ComponentInstanceMethods.pull   = HandleMethods.pull

--[[
    Re-renders this component instance with its last-known props.
    Called by bind/await setters when reactive state changes.
]]
function ComponentInstanceMethods.Render(self: any)
    renderComponentInstance(self, self._props)
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
        _effects       = {},
        _cleanups      = {},
        _connections   = {},
        _containers    = {},
        _pendingContainers = {},
        _slots         = {},
        _slotIdx       = 0,
        _onceFired     = false,
        _ctxSubs       = {},
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
    -- external destruction.  Runs all effect cleanups and disconnects every
    -- connection so nothing outlives the instance.
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
    end)

    _componentInstances[instance] = ci
    return ci
end

--[[
    Runs a full render pass on a ComponentInstance.

    Order of operations mirrors HandleMethods.Render:
      1. Run effect cleanups from the previous pass.
      2. Reset slot index (bind/derive/hold slots are positional).
      3. Store incoming props on the CI for reactive re-renders (bind/await).
      4. Activate lifecycle methods (Effect, Connect, Once, RegisterContainer).
      5. Set _activeHandle = ci so Fragment.compose / useStore / useComponent
         all work correctly inside the component renderer.
      6. Call component._renderer(instance, props, ci).
      7. Restore _activeHandle and deactivate lifecycle methods back to warn stubs.
      8. Run collected effects and store their cleanup functions.

    @param any                  ci    - The ComponentInstance to render
    @param { [string]: any }    props - Props to pass to the renderer
]]
renderComponentInstance = function(ci: any, props: { [string]: any })
    -- 1. Cleanup from previous render: run effect teardowns then disconnect all
    --    connections.  Both are cleared unconditionally before the renderer runs,
    --    giving a clean slate on every pass.  If the renderer subsequently errors,
    --    nothing from the previous pass is left alive — preventing the stale
    --    connection accumulation that occurs when a renderer fails mid-pass.
    for _, cleanup in pairs(ci._cleanups) do
        local ok, err = pcall(cleanup)
        if not ok then
            warn(`[Fragment] Component "{ci._componentName}" instance: effect cleanup error — {err}`)
        end
    end
    table.clear(ci._cleanups)

    for _, conn in pairs(ci._connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(ci._connections)

    -- 2. Reset slot index so bind/derive/hold slots line up correctly
    ci._slotIdx = 0

    -- 3. Store props for reactive re-renders triggered by bind/await
    ci._props = props

    -- 4. Collect effects during this pass
    table.clear(ci._effects)
    local effectIdx = 0

    rawset(ci, "Effect", function(fn: EffectFn)
        effectIdx += 1
        ci._effects[effectIdx] = fn
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
        table.clear(ci._pendingContainers)
        return
    end

    -- 8. Run collected effects, store cleanup functions
    local prevHandle2 = _activeHandle
    _activeHandle = ci
    for i, effectFn in ipairs(ci._effects) do
        local effOk, result = pcall(effectFn)
        if effOk then
            if type(result) == "function" then
                ci._cleanups[i] = result :: () -> ()
            end
        else
            warn(`[Fragment] Component "{ci._componentName}" instance: effect #{i} error — {result}`)
        end
    end
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
                handle:Render()
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
            task.spawn(function() handle:Render() end)
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

    _handleCount += 1

    local handle: any = setmetatable({
        _id = `Handle_{_handleCount}`,
        _name = name,
        _path = path,
        _element = nil   :: Instance?,
        _renderer = nil   :: Renderer?,
        _subscriptions = { name },
        _effects = {}    :: { EffectFn },
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
        _visibilityHooksConnected = false,
        _visibilityConnections = {},
        _rendering = false,

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

    _registry[name] = handle
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