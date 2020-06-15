Library to allow mods to request the creation of 'OR nodes' in the technology tree.

For example, if a mod wants to add a dependency on roboports being unlocked, this is currently not possible, as a roboport is unlocked with either researching construction robots or logistics robots.

OR nodes creates a new 'OR node' (technology) that depends on construction robots or logistic robots, that will be immediately researched when either construction robots or logistic robots has been researched.

Our hypothetical mod then merely needs to depend on the new technology.

```lua
local ORNodes = require('__OR-Nodes__.library').init()

local roboport_technology_name = ORNodes.depend_on_item("roboport")

local prerequisites = {
  "some-other-technology"
}

local technology_name = roboport_technology_name[1]
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

## Or nodes

These produce a technology that is automatically researched when *any* of the prerequisites technologies are researched.

* depend_on_item(item, item_type, silent) - depend on the ability to create item (or fluid).
* depend_on_any_item/depend_on_items(items, silent) - depend on the ability to create at least one of the items (or fluids).
* depend_on_recipe(recipe, silent) - depend on the ability to craft the recipe.
* depend_on_any_recipe/depend_on_recipes(recipes, silent) - depend on the ability to craft at least one of the recipes.
* depend_on_any_technology/depend_on_technologies(technologies, silent) - depend on at least one of the technologies having been researched

There is no depend_on_technology, as that would just return the supplied technology.

## And nodes

These produce a technology that is automatically researched when *all* of the prerequisites technologies are researched.

* depend_on_all_recipe_ingredients(recipe, silent) - depend on the ability to create all of the items required to craft recipe.
* depend_on_all_items(items, silent) - depend on the ability to create all of the items.
* depend_on_all_recipes(recipes, silent) - depend on the ability to craft all of the recipes.
* depend_on_all_technologies(technologies, silent) - depend on all of the technologies having been researched

# Limitations

Does not (yet) automatically determine if a given resource is unlocked or not, if you need to depend on a resource that has its extraction unlocked by research (for example, crude-oil), you will need to supply the technology name yourself.
