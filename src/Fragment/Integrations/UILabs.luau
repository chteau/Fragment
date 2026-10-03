--[[
    Adapter: wrap a Fragment renderer as a UI Labs "Generic" story.

    UI Labs (https://ui-labs.luau.page) previews UI components with live,
    draggable controls. Its library-agnostic story shape uses a `render`
    key instead of `story` to say "this isn't tied to React/Fusion/etc.":

        return {
            controls = { ... },
            render = function(props)   -- props.target, props.controls, props.subscribe
                -- build into props.target, return an optional cleanup function
            end,
        }

    Unlike Flipbook, UI Labs calls `render` exactly once and pushes every
    later control edit through `props.subscribe(fn)` instead of re-calling
    render — dragging a slider fires `fn(values)` live. This adapter keeps
    the latest values in a plain upvalue and calls handle:Render() directly
    on every edit, same as any other reactive trigger in Fragment; no
    throwaway store needed just to carry one update through.

    Usage — in a *.story.luau file, with Fragment installed via Wally:

        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local FragmentModule = ReplicatedStorage.Packages.Fragment
        local Fragment = require(FragmentModule)
        local UILabs = require(FragmentModule.Integrations.UILabs)

        return UILabs.wrap(Fragment, function(element, controls)
            element.Visible = controls.Visible
        end, { Visible = true })

    Fragment is passed in rather than required internally — see Flipbook.luau
    for why.
]]

local UILabs = {}

--[[
    @param Fragment any - The required Fragment module
    @param renderer (element: Instance, controls: { [string]: any }) -> () - Same shape as a Handle's render function
    @param controls { [string]: any }? - Default control values
    @returns any - A UI Labs Generic story table: { controls = controls, render = ... }
]]
function UILabs.wrap(Fragment: any, renderer: (element: Instance, controls: { [string]: any }) -> (), controls: { [string]: any }?): any
    return {
        controls = controls,
        render = function(props: any): () -> ()
            local currentControls = props.controls or {}

            local handle = Fragment.mount(props.target, function(element: Instance)
                renderer(element, currentControls)
            end)

            local unsubscribe = props.subscribe(function(values: { [string]: any })
                currentControls = values
                handle:Render()
            end)

            return function()
                unsubscribe()
                handle:Unmount()
            end
        end,
    }
end

return UILabs
