--[[
    Adapter: wrap a Fragment renderer as a Flipbook story.

    Flipbook (https://devforum.roblox.com/t/2184387) previews UI components
    in an isolated environment. Its vanilla/non-React story shape is:

        return {
            controls = { ... },                        -- optional, plain defaults
            story = function(parent, props)              -- props.controls, props.theme, ...
                -- build into `parent`, return an optional cleanup function
            end,
        }

    This adapter fills in `story` with a Fragment.mount — the one primitive
    Fragment didn't have before mount/unmount existed, since newHandle only
    resolves a pre-placed Studio template by path, and a story's preview
    container is a fresh Instance Flipbook hands you fresh every time.

    Usage — in a *.story.luau file, with Fragment installed via Wally:

        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local FragmentModule = ReplicatedStorage.Packages.Fragment
        local Fragment = require(FragmentModule)
        local Flipbook = require(FragmentModule.Integrations.Flipbook)

        return Flipbook.wrap(Fragment, function(element, controls)
            element.Text = controls.text
        end, { text = "Hello" })

    Fragment is passed in rather than required internally, so this file
    doesn't need to guess where Fragment lives in your project — and so it
    can be unit tested against a fake Fragment the same way Fragment itself
    is tested against fake Roblox Instances.
]]

local Flipbook = {}

--[[
    @param Fragment any - The required Fragment module
    @param renderer (element: Instance, controls: { [string]: any }) -> () - Same shape as a Handle's render function, minus Fragment's own `data` argument (Flipbook has no equivalent)
    @param controls { [string]: any }? - Default control values, Flipbook's own primitive-inferred controls
    @returns any - A Flipbook story table: { controls = controls, story = ... }
]]
function Flipbook.wrap(Fragment: any, renderer: (element: Instance, controls: { [string]: any }) -> (), controls: { [string]: any }?): any
    return {
        controls = controls,
        story = function(parent: Instance, props: any): () -> ()
            local handle = Fragment.mount(parent, function(element: Instance)
                renderer(element, (props and props.controls) or {})
            end)

            return function()
                handle:Unmount()
            end
        end,
    }
end

return Flipbook
