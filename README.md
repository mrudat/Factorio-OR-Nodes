Library to allow mods to request the creation of 'OR nodes' and 'AND nodes' in the technology tree.

# OR Nodes

For example, if a mod wants to add a dependency on roboports being unlocked, this is currently not possible, as a roboport is unlocked with either researching construction robots or logistics robots.

OR nodes allows the creation of a new 'OR node' (technology) that will be immediately researched when any of its prerequisites have been researched.

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

## Functions

Returns a technology name that represents that a force:

* `depend_on_item(item, item_type, silent)` - is able to create the item (or fluid).
* `depend_on_any_item(items, silent)` - is able to create at least one of the items (or fluids).
* `depend_on_recipe(recipe, silent)` - is able to craft the recipe.
* `depend_on_any_recipe(recipes, silent)` - is able to craft at least one of the recipes.
* `depend_on_any_technology(technologies, silent)` - has researched at least one of the technologies.

There is no depend_on_technology, as that would just return the supplied technology.

# AND Nodes

'AND Nodes' are to support the case where the resulting technology is an obvious consequence of the parent technologies being researched. For example, a recipe that loads a gun turret with uranium rounds should not require further research once both turrets and uranium rounds can be created.

```lua
local ORNodes = require('__OR-Nodes__.library').init()

local recipe = {
  type = "recipe"
  name = "gun-turret-with-uranium-rounds-magazine",
  ingredients = {
    {"gun-turret", 1},
    {"uranium-rounds-magazine", 10}
  },
  ...
}

local recipe_technology_name = ORNodes.depend_on_all_recipe_ingredients(recipe)

local technology_name = recipe_technology_name[1]
if technology_name then
  local technology = data.raw.technology[technology_name]
  local effects = technology.effects
  if not effects then
    effects = {}
    technology.effects = effects
  end

  recipe.enabled = false

  table.insert(effects, {
    type = "unlock-recipe",
    recipe = "gun-turret-with-uranium-rounds-magazine"
  })
end
```

## Functions

These produce a technology that is automatically researched when *all* of the prerequisites technologies are researched.

Returns a technology name that represents that a force:

* `depend_on_all_recipe_ingredients(recipe, silent)` - is able to create all of the items required to craft the recipe.
* `depend_on_all_items(items, silent)` - is able to create all of the items.
* `depend_on_all_recipes(recipes, silent)` - is able to craft all of the recipes.
* `depend_on_all_technologies(technologies, silent)` - has researched all of the technologies.

# Allowed inputs

When supplying a list of things (items, recipes, technologies), you may supply the things in a number of different formats:

* the name of the thing as a string
* for items (or fluids) only, you can supply a table to allow specifying fluids or items.

  * `{ name = 'item-1', type = 'item' }`
  * `{ 'fluid-1', 'fluid' }`
  * `{ type='fluid, 'fluid-2' }`

* you can supply a dictionary of things as keys, with a value indicating the difficulties (normal/expensive) for which those things are required.

```lua
-- Requires roboports and iron-gear-wheels on both difficulties, the fluid tender-loving-care for expensive, and tough-love in normal
local items = {
  roboport = 3, -- DIFFICULTIES_BOTH 0b11
  [{type = 'fluid', 'tender-loving-care'}] = 2, -- DIFFICULTIES_EXPENSIVE 0b10
  ['tough-love'] = 1, -- DIFFICULTIES_NORMAL 0b01
  'iron-gear-wheel' -- both difficulties if unstated.
}

local technology = ORNodes.depend_on_all_items(items)
```

# Return values

* A list of 1 technology name representing the requested condition
* An empty list when the requested condition is satisfied without any research

## On error

* raises an error by default
* returns nil if the silent option is set to true

# Limitations

The difficulty support hasn't been well tested.

Can't discover that a technology or recipe is unlocked by script, or that an item is created by script. You're going to have to determine what technology to depend upon by investigation.

# TODO

Does not (yet) support depending on:

* mining results from arbitrary autoplaced entities (Wood from trees)
* items created by a shortcut (that might be unlocked by a technology)
* Fish - a category all of their own
* loot from killing units
* water from an offshore pump

Still working on simplifying dependencies for And nodes.
