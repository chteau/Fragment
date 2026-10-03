local Signal = require("./Signal")

--[[
    Minimal fake Roblox Instance used to drive Fragment.luau outside of
    Roblox Studio. Only implements the surface Fragment actually touches:
    Name/Parent/Visible, FindFirstChild/WaitForChild/GetChildren, IsA via a
    small class-hierarchy table, GetPropertyChangedSignal, Destroy/
    Destroying, SetAttribute/GetAttribute/GetAttributeChangedSignal, and an
    Activated signal (the one event Fragment.create's OnEvent is tested
    against).

    Parent is a real property, not a test-setup helper: assigning it
    (`child.Parent = frame`) reparents for real, same as Roblox — this
    matters now that Fragment.create parents [Children] by just setting
    Parent directly, the same way real Fragment/Roblox code does.

    WaitForChild does NOT yield like the real one — tests build their whole
    tree up front, so a miss behaves like FindFirstChild (immediate nil)
    rather than hanging the test runner forever.
]]

local HIERARCHY: { [string]: { string } } = {
    PlayerGui  = {},
    ScreenGui  = { "LayerCollector" },
    Frame      = { "GuiObject", "GuiBase2d" },
    TextButton = { "GuiButton", "GuiObject", "GuiBase2d" },
    TextLabel  = { "GuiObject", "GuiBase2d" },
    Folder     = {},
}

local FakeInstance = {}

local function removeFromParent(inst: any)
    local parent = rawget(inst, "_parent")
    if not parent then return end
    local siblings = parent._children
    for i, child in ipairs(siblings) do
        if child == inst then
            table.remove(siblings, i)
            break
        end
    end
end

local InstanceMeta = {}

InstanceMeta.__index = function(inst: any, key: string): any
    if key == "Parent" then
        return rawget(inst, "_parent")
    end
    return FakeInstance[key]
end

InstanceMeta.__newindex = function(inst: any, key: string, value: any)
    if key == "Parent" then
        removeFromParent(inst)
        rawset(inst, "_parent", value)
        if value then
            table.insert(value._children, inst)
        end
    else
        rawset(inst, key, value)
    end
end

function FakeInstance.new(className: string, name: string?): any
    local self = setmetatable({
        ClassName = className,
        Name = name or className,
        Visible = true,
        Enabled = true,
        Activated = Signal.new(),
        Destroying = Signal.new(),
        _parent = nil :: any,
        _children = {} :: { any },
        _propertySignals = {} :: { [string]: any },
        _attributes = {} :: { [string]: any },
        _attributeSignals = {} :: { [string]: any },
        _destroyed = false,
    }, InstanceMeta)

    return self
end

function FakeInstance:IsA(className: string): boolean
    if className == self.ClassName then return true end
    local supers = HIERARCHY[self.ClassName]
    if supers then
        for _, super in ipairs(supers) do
            if super == className then return true end
        end
    end
    return false
end

--[[
    Parents `child` under this instance — a convenience for test setup,
    equivalent to `child.Parent = self`.
]]
function FakeInstance:AddChild(child: any)
    child.Parent = self
end

function FakeInstance:FindFirstChild(name: string): any
    for _, child in ipairs(self._children) do
        if child.Name == name then return child end
    end
    return nil
end

FakeInstance.WaitForChild = FakeInstance.FindFirstChild

function FakeInstance:GetChildren(): { any }
    local copy = {}
    for i, child in ipairs(self._children) do
        copy[i] = child
    end
    return copy
end

function FakeInstance:GetPropertyChangedSignal(prop: string): any
    if not self._propertySignals[prop] then
        self._propertySignals[prop] = Signal.new()
    end
    return self._propertySignals[prop]
end

function FakeInstance:SetAttribute(name: string, value: any)
    self._attributes[name] = value
    local signal = self._attributeSignals[name]
    if signal then
        signal:Fire()
    end
end

function FakeInstance:GetAttribute(name: string): any
    return self._attributes[name]
end

function FakeInstance:GetAttributeChangedSignal(name: string): any
    if not self._attributeSignals[name] then
        self._attributeSignals[name] = Signal.new()
    end
    return self._attributeSignals[name]
end

function FakeInstance:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    self.Destroying:Fire()
    self.Parent = nil
end

return FakeInstance
