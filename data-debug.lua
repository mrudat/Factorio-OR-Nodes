local ORNodes = require('__OR-Nodes__/library.lua').init()

local function logt(table) log(serpent.block(table)) end

local ok, result, message

log('--- tests for single items')

log('new technology required to depend on roboport')
result = ORNodes.depend_on_item("roboport")
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-item-item-roboport')

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
result = ORNodes.depend_on_items({ "accumulator", "gun-turret" })
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-items-item-accumulator-or-item-gun-turret')

log('depend on a set of items where at least one is unlocked at the start')
result = ORNodes.depend_on_items({ "iron-stick", "gun-turret" })
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('depend on a set of items where at least one is unlocked at the start, and the other does not exist')
result = ORNodes.depend_on_items({"does-not-exist", "iron-stick"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('fail to depend on a set of items where none of the items exist')
result = ORNodes.depend_on_items({"does-not-exist", "also-does-not-exist"}, true)
assert(result == nil)

log('--- tests single-item items requirements')

log('new technology required to depend on roboport')
result = ORNodes.depend_on_items({"roboport"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-item-item-roboport')

log('no technology returned, as iron-gear-wheel is unlocked from the start')
result = ORNodes.depend_on_items({"iron-gear-wheel"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('silently fail to create technology for an item that does not exist')
result = ORNodes.depend_on_items({"does-not-exist"}, true)
assert(result == nil)

log('no technology returned, as depending on no items at all')
result = ORNodes.depend_on_items({})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('--- tests for depending on a recipe')

log('depend on ability to perform a vanilla recipe')
result = ORNodes.depend_on_recipe("assembling-machine-1")
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'automation')

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
result = ORNodes.depend_on_recipes({"artillery-shell", "coal-liquefaction"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'OR-Nodes-recipes-artillery-shell-or-coal-liquefaction')

log('depend on a set of recipes where at least one is unlocked at the start')
result = ORNodes.depend_on_recipes({"iron-stick", "coal-liquefaction"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('depend on a set of recipes where one is unlocked at the start, and the other does not exist')
result = ORNodes.depend_on_recipes({"iron-stick", "does-not-exist"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('fail to depend on a set of recipes where none of the items exist')
result = ORNodes.depend_on_recipes({"does-not-exist", "also-does-not-exist"}, true)
assert(result == nil)

log('depend on ability to perform a vanilla recipe')
result = ORNodes.depend_on_recipes({"assembling-machine-1"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'automation')

log('no technology returned, as iron-gear-wheel is unlocked from the start')
result = ORNodes.depend_on_recipes({"iron-gear-wheel"})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('silently fail to create technology for a recipe that does not exist')
result = ORNodes.depend_on_recipes({"does-not-exist"}, true)
assert(result == nil)

log('no technology returned, as we depend on no recipes at all')
result = ORNodes.depend_on_recipes({})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('--- tests for depending on a set of technologies')

log('depend on a set of technologies that need a new technology')
result = ORNodes.depend_on_technologies({"speed-module", "energy-weapons-damage-1"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == "OR-Nodes-technologies-energy-weapons-damage-1-or-speed-module")

log('depend on a set of technologies where only one exists')
result = ORNodes.depend_on_technologies({"speed-module", "does-not-exist"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'speed-module')

log('depend on a set of technologies where none of them exist')
result = ORNodes.depend_on_technologies({"also-does-not-exist", "does-not-exist"}, true)
assert(result == nil)

log('depend on only a single technology')
result = ORNodes.depend_on_technologies({"speed-module"})
logt(result)
assert(type(result) == 'table')
assert(result[1] == 'speed-module')

log('depend on no technologies')
result = ORNodes.depend_on_technologies({})
logt(result)
assert(type(result) == 'table')
assert(#result == 0)

log('--- exercising name list assembly')

log('depend on one of 3 items')
ORNodes.depend_on_items({"piercing-rounds-magazine", "filter-inserter", "power-armor"})

log('depend on one of 4 items')
ORNodes.depend_on_items({"piercing-rounds-magazine", "filter-inserter", "power-armor", "assembling-machine-1"})

log('depend on one of 5 items')
ORNodes.depend_on_items({"piercing-rounds-magazine", "filter-inserter", "power-armor", "assembling-machine-1", "logistic-chest-buffer"})
