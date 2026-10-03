local FakeInstance = require("./Instance")
local Signal = require("./Signal")

--[[
    Builds a fake `game` plus a PlayerGui fixture — the minimum Roblox
    surface Fragment.luau touches at the top level (Players.LocalPlayer,
    TweenService, RunService) and inside useComponent (bare `game`).

    Fragment reads `game`/`Players`/`TweenService`/`RunService` as plain
    globals, so the caller must assign the returned `game` to the real
    global `game` BEFORE requiring Fragment.luau — see tests/Fragment.spec.luau.

    RunService.Heartbeat is a plain Signal the test suite fires manually
    (env.heartbeat:Fire(dt)) to step springs deterministically, instead of
    waiting on real frame timing.
]]
local function makeEnv(): any
    local playerGui = FakeInstance.new("PlayerGui", "PlayerGui")

    local localPlayer: any = { Name = "TestPlayer" }
    function localPlayer:FindFirstChild(name: string): any
        if name == "PlayerGui" then return playerGui end
        return nil
    end
    localPlayer.WaitForChild = localPlayer.FindFirstChild

    local players = { LocalPlayer = localPlayer }

    local tweenService = {
        Create = function(_self: any, _instance: any, _info: any, _props: any): any
            return {
                Play = function() end,
                Cancel = function() end,
                Completed = Signal.new(),
            }
        end,
    }

    local heartbeat = Signal.new()
    local runService = { Heartbeat = heartbeat }

    local services: { [string]: any } = {
        Players = players,
        TweenService = tweenService,
        RunService = runService,
    }

    local game = {
        GetService = function(_self: any, name: string): any
            return services[name]
        end,
    }

    return {
        game = game,
        players = players,
        tweenService = tweenService,
        runService = runService,
        heartbeat = heartbeat,
        playerGui = playerGui,
    }
end

return makeEnv
