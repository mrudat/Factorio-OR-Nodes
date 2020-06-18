-- create some test records.
-- TODO make the tests work against core, rather than requiring base.

-- TODO exercise depend_on_all_recipe_ingredeints
-- TODO exercise depend_on_all_items
-- TODO exercise depend_on_all_recipes
-- TODO exercise depend_on_all_technologies

local name_counter = {}

local function make_name(type)
  local count = name_counter[type]
  if not count then
    count = 1
  else
    count = count + 1
  end
  name_counter[type] = count
  -- don't end with a number so that we don't look like infinite technology?
  return 'Test Mod-' .. type .. '-' .. count .. '-'
end

local function pad_name(name, target_length)
  if not target_length then target_length = 100 end
  local length = name:len()
  local padding = math.ceil((target_length - length)/26)
  name = name .. ('abcdefghijklmnopqrstuvwxyz'):rep(padding)
  name = name:sub(1,target_length)
  if name:len() ~= target_length then error("?!") end
  return name
end

local icons = {
  {
    icon = "__core__/graphics/empty.png",
    icon_size = 1
  }
}

local unit = {
  count = 1,
  ingredients = {
    {"automation-science-pack", 1},
  },
  time = 1
}

local function new_item(name, item_data)
  if not item_data then item_data = {} end
  if not item_data.stack_size then item_data.stack_size = 50 end
  item_data.type = "item"
  item_data.name = name
  item_data.icons = icons
  item_data.localised_name = { "", name }
  item_data.localised_description = { "", name }
  data:extend{ item_data }
end

local function new_recipe(name, is_enabled, recipe_data)
  if not recipe_data then recipe_data = {} end
  if not recipe_data.ingredients then recipe_data.ingredients = {} end
  if not recipe_data.result or recipe_data.results then
    recipe_data.results = {}
    -- other is the default subgroup of an item
    recipe_data.subgroup = "other"
  end
  if not is_enabled then
    recipe_data.enabled = false
  end
  recipe_data.type = "recipe"
  recipe_data.name = name
  recipe_data.icons = icons
  recipe_data.localised_name = { "", name }
  recipe_data.localised_description = { "", name }
  data:extend{ recipe_data }
end

local function new_technology(name, technology_data)
  if not technology_data  then technology_data = {} end
  technology_data.type = "technology"
  technology_data.name = name
  technology_data.icons = icons
  technology_data.unit = unit
  technology_data.localised_name = { "", name }
  technology_data.localised_description = { "", name }
  data:extend{ technology_data }
end

local long_name_test = {}

long_name_test.long_recipe_1=pad_name(make_name('recipe'), 200)
long_name_test.long_technology_1=pad_name(make_name('technology'))
long_name_test.long_technology_2=pad_name(make_name('technology'))

new_recipe(long_name_test.long_recipe_1)
new_technology(long_name_test.long_technology_1, {
  effects = {
    {
      type = "unlock-recipe",
      recipe = long_name_test.long_recipe_1
    }
  }
})
new_technology(long_name_test.long_technology_2, {
  effects = {
    {
      type = "unlock-recipe",
      recipe = long_name_test.long_recipe_1
    }
  }
})

local all_recipe_ingredients = {}

all_recipe_ingredients.one_ingredient_requires_research = make_name('recipe')
new_recipe(all_recipe_ingredients.one_ingredient_requires_research, true, {
  ingredients = {
    {"gun-turret", 1},
    {"firearm-magazine", 10}
  }
})

all_recipe_ingredients.both_ingredients_require_research = make_name('recipe')
new_recipe(all_recipe_ingredients.both_ingredients_require_research, true, {
  ingredients = {
    {"gun-turret", 1},
    {"piercing-rounds-magazine", 10}
  }
})

all_recipe_ingredients.both_ingredients_require_same_research = make_name('recipe')
new_recipe(all_recipe_ingredients.both_ingredients_require_same_research, true, {
  ingredients = {
    {"artillery-turret", 1},
    {"artillery-shell", 5}
  }
})

local list_length_test_names = {}

for _ = 1, 20 do
  local item_name = make_name('item')
  table.insert(list_length_test_names, item_name)
  new_item(item_name)
  new_recipe(item_name, nil, {
    result = item_name
  })
  new_technology(item_name, {
    effects = {
      {
        type = "unlock-recipe",
        recipe = item_name
      }
    }
    })
end

-- we build an index in init of tech/items/recipes, so we need to init after adding our test prototypes.
local ORNodes = require('__OR-Nodes__/library.lua').init()

local function logt(table) log(serpent.block(table)) end

local ok, result, message

log('--- tests for single items')

log('depend on mining a fluid')
result = ORNodes.depend_on_item("crude-oil", "fluid")
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'oil-processing')

log('new technology required to depend on roboport')
result = ORNodes.depend_on_item("roboport")
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-or-items-item-roboport')

log('no technology returned, as iron-gear-wheel is unlocked from the start')
result = ORNodes.depend_on_item("iron-gear-wheel")
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('silently fail to create technology for an item that does not exist')
result = ORNodes.depend_on_item("does-not-exist", nil, true)
assert(result == nil)

log('error to create technology for an item that does not exist')
ok, message = pcall(ORNodes.depend_on_item, "does-not-exist", nil)
assert(ok == false)
log(message)

log('--- tests for a set of items')

log('depend on a set of items that need a new technology')
result = ORNodes.depend_on_any_item({ "accumulator", "gun-turret" })
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-or-items-item-accumulator-or-item-gun-turret')

log('depend on a set of items where at least one is unlocked at the start')
result = ORNodes.depend_on_any_item({ "iron-stick", "gun-turret" })
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('depend on a set of items where at least one is unlocked at the start, and the other does not exist')
result = ORNodes.depend_on_any_item({"does-not-exist", "iron-stick"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('fail to depend on a set of items where none of the items exist')
result = ORNodes.depend_on_any_item({"does-not-exist", "also-does-not-exist"}, true)
assert(result == nil)

log('--- tests single-item items requirements')

log('new technology required to depend on roboport')
result = ORNodes.depend_on_any_item({"roboport"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-or-items-item-roboport')

log('no technology returned, as iron-gear-wheel is unlocked from the start')
result = ORNodes.depend_on_any_item({"iron-gear-wheel"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('silently fail to create technology for an item that does not exist')
result = ORNodes.depend_on_any_item({"does-not-exist"}, true)
assert(result == nil)

log('no technology returned, as depending on no items at all')
result = ORNodes.depend_on_any_item({})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('--- tests for depending on a recipe')

log('depend on ability to perform a vanilla recipe')
result = ORNodes.depend_on_recipe("assembling-machine-1")
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'automation')

log('depend on ability to perform a recipe with a 200 character name')
result = ORNodes.depend_on_recipe(long_name_test.long_recipe_1)
logt(result)
assert(type(result) == 'table')
assert(result[1] ~= nil)

log('no technology returned, as iron-gear-wheel is unlocked from the start')
result = ORNodes.depend_on_recipe("iron-gear-wheel")
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('silently fail to create technology for a recipe that does not exist')
result = ORNodes.depend_on_recipe("does-not-exist", true)
assert(result == nil)

log('--- tests for depending on a set of recipes')

log('depend on a set of recipes that need a new technology')
result = ORNodes.depend_on_any_recipe({"artillery-shell", "coal-liquefaction"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-or-recipes-artillery-shell-or-coal-liquefaction')

log('depend on a set of recipes where at least one is unlocked at the start')
result = ORNodes.depend_on_any_recipe({"iron-stick", "coal-liquefaction"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('depend on a set of recipes where one is unlocked at the start, and the other does not exist')
result = ORNodes.depend_on_any_recipe({"iron-stick", "does-not-exist"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('fail to depend on a set of recipes where none of the items exist')
result = ORNodes.depend_on_any_recipe({"does-not-exist", "also-does-not-exist"}, true)
assert(result == nil)

log('depend on ability to perform a vanilla recipe')
result = ORNodes.depend_on_any_recipe({"assembling-machine-1"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'automation')

log('no technology returned, as iron-gear-wheel is unlocked from the start')
result = ORNodes.depend_on_any_recipe({"iron-gear-wheel"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('silently fail to create technology for a recipe that does not exist')
result = ORNodes.depend_on_any_recipe({"does-not-exist"}, true)
assert(result == nil)

log('no technology returned, as we depend on no recipes at all')
result = ORNodes.depend_on_any_recipe({})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('--- tests for depending on a set of technologies')

log('depend on a set of technologies that need a new technology')
result = ORNodes.depend_on_any_technology({"speed-module", "energy-weapons-damage-1"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == "OR-Nodes-or-technologies-energy-weapons-damage-1-or-speed-module")

log('depend on a set of technologies where only one exists')
result = ORNodes.depend_on_any_technology({"speed-module", "does-not-exist"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'speed-module')

log('depend on a set of technologies where none of them exist')
result = ORNodes.depend_on_any_technology({"also-does-not-exist", "does-not-exist"}, true)
assert(result == nil)

log('depend on only a single technology')
result = ORNodes.depend_on_any_technology({"speed-module"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'speed-module')

log('depend on no technologies')
result = ORNodes.depend_on_any_technology({})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('--- exercising name list assembly')

log('depend on one of 3 items')
ORNodes.depend_on_any_item({"piercing-rounds-magazine", "filter-inserter", "power-armor"})

log('depend on one of 4 items')
ORNodes.depend_on_any_item({"piercing-rounds-magazine", "filter-inserter", "power-armor", "assembling-machine-1"})

log('depend on one of 5 items')
ORNodes.depend_on_any_item({"piercing-rounds-magazine", "filter-inserter", "power-armor", "assembling-machine-1", "logistic-chest-buffer"})

log('depend on one of 20 items - this has to have the list truncated as there is a nesting limit of 20')
ORNodes.depend_on_any_item(list_length_test_names)

log('--- depend on all items for recipe')

log('depend on recipe ingredients where at least one is unlocked from the start')
result = ORNodes.depend_on_all_recipe_ingredients(all_recipe_ingredients.one_ingredient_requires_research,true)
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'turrets')

data.raw.recipe[all_recipe_ingredients.one_ingredient_requires_research].enabled = false

table.insert(data.raw.technology[result[1]].effects,
  {
    type = "unlock-recipe",
    recipe = all_recipe_ingredients.one_ingredient_requires_research
  }
)

log('depend on recipe ingredients where at both require different research')
result = ORNodes.depend_on_all_recipe_ingredients(all_recipe_ingredients.both_ingredients_require_research,true)
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-and-recipe-Test Mod-recipe-3-')

data.raw.recipe[all_recipe_ingredients.both_ingredients_require_research].enabled = false

data.raw.technology[result[1]].effects = {
  {
    type = "unlock-recipe",
    recipe = all_recipe_ingredients.both_ingredients_require_research
  }
}

log('depend on recipe ingredients where at both require the same research')
result = ORNodes.depend_on_all_recipe_ingredients(all_recipe_ingredients.both_ingredients_require_same_research,true)
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'artillery')

data.raw.recipe[all_recipe_ingredients.both_ingredients_require_same_research].enabled = false

table.insert(data.raw.technology[result[1]].effects,
  {
    type = "unlock-recipe",
    recipe = all_recipe_ingredients.both_ingredients_require_same_research
  }
)


log('--- depend on all items')

log('depend on all of a set of items that need a new technology')
result = ORNodes.depend_on_all_items({ "accumulator", "gun-turret" },true)
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-and-items-item-accumulator-and-item-gun-turret')

log('depend on all of a set of items where at least one is unlocked at the start')
result = ORNodes.depend_on_all_items({ "iron-stick", "gun-turret" },true)
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'turrets')

log('fail to depend on all of a set of items where at one does not exist')
result = ORNodes.depend_on_all_items({"does-not-exist", "iron-stick"},true)
assert(result == nil)


log("--- depend on all recipes")

log('depend on all of a set of recipes that need a new technology')
result = ORNodes.depend_on_all_recipes({ "accumulator", "gun-turret" },true)
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-and-recipes-accumulator-and-gun-turret')

log('depend on all of a set of recipes where at least one is unlocked at the start')
result = ORNodes.depend_on_all_recipes({ "iron-stick", "gun-turret" },true)
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'turrets')

log('fail to depend on all of a set of recipes where at one does not exist')
result = ORNodes.depend_on_all_recipes({"does-not-exist", "iron-stick"},true)
assert(result == nil)


log("--- depend on all technologies")

log('depend on all of a set of technologies that need a new technology')
result = ORNodes.depend_on_all_technologies({ "electric-energy-accumulators", "turrets" },true)
logt(result)
assert(type(result) == 'table')
assert(result[1] == "OR-Nodes-and-technologies-electric-energy-accumulators-and-turrets")

log('fail to depend on all of a set of technologies where at one does not exist')
result = ORNodes.depend_on_all_technologies({"does-not-exist", "turrets"},true)
assert(result == nil)


log("all tests passed")
