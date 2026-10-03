--[[
    Minimal fake of an RBXScriptSignal/RBXScriptConnection pair — just enough
    to Connect, Disconnect and Fire. Used by the Instance mock so GetProperty-
    ChangedSignal and Destroying behave like the real thing.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = {
    Connected: boolean,
    Disconnect: (self: Connection) -> (),
}

function Signal.new()
    return setmetatable({
        _nextId = 0,
        _listeners = {} :: { [number]: (...any) -> () },
    }, Signal)
end

function Signal:Connect(fn: (...any) -> ()): Connection
    self._nextId += 1
    local id = self._nextId
    self._listeners[id] = fn

    local listeners = self._listeners
    local connection: any = { Connected = true }
    connection.Disconnect = function(self: any)
        self.Connected = false
        listeners[id] = nil
    end

    return connection
end

function Signal:Fire(...: any)
    for _, fn in pairs(self._listeners) do
        fn(...)
    end
end

return Signal
