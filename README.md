Allows mods to request the creation of 'OR nodes' in the technology tree.

For example, if a mod wants to add a dependency on roboports being unlocked, this is currently not possible, as a roboport is unlocked with either researching construction robots or logistics robots.

OR nodes creates a new 'OR node' (technology) that depends on construction robots or logistic robots, that will be immediately researched when either construction robots or logistic robots has been researched.

Our hypothetical mod then merely needs to depend on the new technology.

```lua
local ORNodes = require('__OR-Nodes__/library.lua').init()

local roboport_technology_name = ORNodes.depend_on_item("roboport")

local prerequisites = {
  "some-other-technology"
}

local technology_name = next(roboport_technology_name)
if technology_name then
  table.insert(prerequisites, technology_name)
end

data:extend({
  {
    type = "technology",
    name = "my-nifty-thing",
    prerequisites = prerequisites,
    ...
  }
})
```

# Return values

* A list of 1 technology name representing the requested condition
* An empty list when the requested condition is satisfied without any research

## On error

* raises an error by default
* returns nil if the silent option is set to true

# Functions

* depend_on_item(item, item_type, silent) - depend on the ability to create item (or fluid).
* depend_on_items(items, silent) - depend on the ability to create at least one of the items.
* depend_on_recipe(recipe, silent) - depend on ability to craft the recipe.
* depend_on_recipes(recipes, silent) - depend on ability to craft at least one of the recipes.
* depend_on_technologies(technologies, silent) - depend on at least one of the technologies being researched

There is no depend_on_technology, as that would just return the supplied technology.
