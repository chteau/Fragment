<br/>
<div align="center">
    <h1 align="center">
        Fragment.luau
    </h1>
    <br>
    <br>
    <a href="https://github.com/chteau/Fragment">
        <img src="https://raw.githubusercontent.com/chteau/Fragment/refs/heads/main/img/LogoWhite.png" alt="Banner" width="100">
    </a>
    <br>
    <br>
    <div align="center">
        <img src="https://img.shields.io/badge/Luau-3057FD?style=for-the-badge&logo=lua&logoColor=white" alt="Luau Badge" />
    </div>
    <br/>
</div>

Fragment is a simple module I made to manage Roblox's imperative UI instance system inspired by React. It currently supports state management, effects, declarative rendering, globals stores, re-usable components which allow you to build reactive user interfaces whilst still using default Roblox's UI components.

To learn more or get more details on the installation and available methods, [read the docs](https://chteau.github.io/Fragment/) here.

## Installation

1. Insert a ModuleScript named `Fragment` into `ReplicatedStorage`.
2. Paste the [source code](https://github.com/chteau/Fragment/blob/main/Fragment.luau) of Fragment into the ModuleScript you just created.
3. Created a folder for your UI (e.g., `MySuperDuperUI`) somwehere like in `StarterPlayerScripts`.

And there you go, you got Fragment in your project! 🗣️

## Setting-Up Fragment

Once you installed Fragment and created the folder (e.g., `MySuperDuperUI`), you may now start using it. For your projects, I recommend using this structure:
```
.
└── StarterPlayerScripts/
    └── MySuperDuperUI/
        ├── FragmentLoad.client.luau -- This will be used to init a Fragment singleton instance
        ├── Components/
        │   └── ...
        ├── Handles/
        │   └── ...
        ├── Hooks/
        │   └── ...
        └── Stores/
            └── ...
```

Now, in `FragmentLoad.client.luau` :: `LocalScript` you can now directly require the `Fragment` ModuleScript you installed and load your handles.
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fragment = require(ReplicatedStorage.Fragment)

-- Load all your modulescripts here!
Fragment.load({
    Stores = script.Parent.Stores,
    Contexts = script.Parent.Contexts,
    Hooks = script.Parent.Hooks,
    Components = script.Parent.Components,
    Handles = script.Parent.Handles,
})
```

That's it! You can see a bit of the API references and some examples in this readme or you can head to the [Github Wiki](https://chteau.github.io/Fragment/) to find out how it works in details.

## Core Concepts

Fragment runs as a singleton across your whole client and can be required everywhere in your Handles, Stores, Hooks and Contexts.

### 1. Handles
Handles bind logic to specific UI instances. They are created using `Fragment.newHandle` and define a **Rendered Function** that runs whenever the state of your handle changes.
```luau
local Handle = Fragment.newHandle("MyButton", { "ScreenGui", "Frame", "TextButton" })

return Handle(function(Element: TextButton)
  element.Text = "Click me"

  Handle.Connect("Click", element.Activated, function()
    print("Button clicked")
  end)
end
```

### 2. Local State (`bind`)
You can manage your local handle's state similar to React's `useState` hook.
```luau
local count, setCount = Handle:bind(0)

Handle.Connect("Increment", button.Activated, function()
  setCount(count() + 1)
end)

element.Text = `Count: {count()}`
```

### 3. Global Stores (`createStore`)
You can also create centralized state management stores accessible across multiple handles.
```luau
-- Definition
return Fragment.createStore("PlayerData", function(set, get)
  return {
    Coins = 0,
    addCoins = function(amount: number)
      set({ Coins = get().Coins + amount })
    end
  }
end)

-- Usage in a Handle
local store = Fragment.useStore("PlayerData")
element.Text = `Coins: {store.Coins}`
```
This way of creating stores is really similar to [Zustand](https://zustand.docs.pmnd.rs/learn/getting-started/introduction) (*for React*), and I did inspire myself from it to make this.

### 4. Context and Custom Hooks (`compose`)
You can share logic between handles using what's called Contexts and Composable functions.
```luau
-- New Context
local WindowContext = Fragment.createContext({ active = nil })

-- Custom Hook
local useWindow = Fragment.compose(function(handle, windowName)
  local ctx = handle:pull(WindowContext)
  local isOpen = handle:derive(function()
    return ctx.active == windowName
  end, { ctx.active })

  return isOpen, ctx
end)
```

### 5. Re-usable Components
You can finally create re-usable components you can call through your different handles.
```luau
-- New Component
local Component = Fragment.newComponent("ListItem", { "ScreenGui", "Assets", "ListItem" })

return Component(function(element, props)
     element.Text = props.Price
end)
```
```luau
local Handle = Fragment.newHandle(..., ...)

return Handle(function(element)
    local Store = Fragment.useStore(...)
    local Data = Store.getData()

    local Container = Handle.RegisterContainer(...)
    for _, entry in Data.Entries do
        local Item = Fragment.useComponent(name, { Price = math.random() }) -- Automatically returns a clone
        local live = Container.UpsertChild(Item)
        -- ...
    end
end)
```

## Possible Usages

You can pretty much use Fragment for anything. In my case, I use it with [ReplicaService](https://devforum.roblox.com/t/replicate-your-states-with-replicaservice-networking-system/894736) and [Knit](https://sleitnick.github.io/Knit/). I really like react and since most of the people I work with don't use it's luau version and bake the UI directly using Roblox's Studio interface manager (if I may call it like that), I thought it would be pretty cool to have such a ressource out there; maybe there's other more complete frameworks for that on roblox but I didn't find any so, here it is.

## Conclusion

Again, if you wanna know how things work in more details, check out the [Github Wiki](https://chteau.github.io/Fragment/) for API references and usage examples. Peace!
