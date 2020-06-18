local F = _ENV['OR-Nodes']
if F then
  F.init()
  return F
else
  F = {}
  _ENV['OR-Nodes'] = F
end

log("Loading OR-Nodes library...")





--------------------------------------------------------------------------------
-- imports

local rusty_locale = require('__rusty-locale__.locale')
local rusty_icons = require('__rusty-locale__.icons')
local rusty_prototypes = require('__rusty-locale__.prototypes')
local HighlyDerivative
if mods['HighlyDerivative'] then
  HighlyDerivative = require('__HighlyDerivative__.library')
end

local locale_of = rusty_locale.of
local icons_of = rusty_icons.of
local find_prototype = rusty_prototypes.find

local bor = bit32.bor
local band = bit32.band
local lshift = bit32.lshift
local bnot = bit32.bnot





--------------------------------------------------------------------------------
-- constants

local MOD_NAME = "OR-Nodes"
local PREFIX_OR = MOD_NAME .. "-or-"
local PREFIX_AND = MOD_NAME .. "-and-"
local MOD_PATH = "__" .. MOD_NAME .. "__/"
-- local GRAPHICS_PATH = ("__%s__/graphics/"):format(MOD_NAME)
local OR_ICON = MOD_PATH .. "thumbnail.png"
-- TODO create icon.
--local AND_ICON = MOD_PATH .. "graphics/and.png"

-- recipe flags
F['AVAILABLE_BY_DEFAULT_MASK'] = 12 --[[AVAILABLE_BY_DEFAULT_MASK]]
F['AVAILABLE_BY_DEFAULT_EXPENSIVE'] = 8 --[[AVAILABLE_BY_DEFAULT_EXPENSIVE]]
F['AVAILABLE_BY_DEFAULT_NORMAL'] = 4 --[[AVAILABLE_BY_DEFAULT_NORMAL]]
F['AVAILABLE_BY_DEFAULT_BOTH'] = 12 --[[AVAILABLE_BY_DEFAULT_BOTH]]


-- difficulty 'constants'
F['DIFFICULTY_EXPENSIVE'] = 2 --[[DIFFICULTY_EXPENSIVE]]
F['DIFFICULTY_NORMAL'] = 1 --[[DIFFICULTY_NORMAL]]
F['DIFFICULTY_BOTH']  = 3 --[[DIFFICULTY_BOTH]]
F['DIFFICULTY_MASK'] = 3 --[[DIFFICULTY_MASK]]





--------------------------------------------------------------------------------
-- package variables

F.recipe_name_to_technology_names = {}
F.technology_name_to_dependent_technology_names = {}
F.technology_name_to_prerequisite_technology_names = {}
F.drill_index = {}
F.drill_placeable_by = {}
F.items_that_place = {}
F.recipe_index = {}
F.resource_data_by_type_and_item = {}
F.new_technologies = {}
F.unnamed_or_node_count = 1
F.unnamed_and_node_count = 1





--------------------------------------------------------------------------------
-- small utility functions

local function hash(input_string)
  local h = 0
  for _,c in ipairs{string.byte(input_string,1,-1)} do
    h = band(h * 31 + c, 0xffff)
  end
  return string.format("%8.8X",h)
end

local function autovivify(table, key)
  local foo = table[key]
  if not foo then
    foo = {}
    table[key] = foo
  end
  return foo
end

local function report_error(is_silent, levels, message)
  if is_silent then
    log(message)
    return nil
  else
    error(message, levels + 1)
  end
end






--------------------------------------------------------------------------------
-- index various things

local function collect_items_to_mine_item(item_names, item, difficulties)
  local item_type = item.type
  if item_type ~= 'item' then item_type = 'fluid' end

  local resource_data_by_item = F.resource_data_by_type_and_item[item_type]
  if not resource_data_by_item then return end

  local item_name = item.name

  local resource_data_by_resource_name = resource_data_by_item[item_name]
  if not resource_data_by_resource_name then return end

  local drill_index = F.drill_index

  local is_fluid = item_type == 'fluid'

  local mining_drills = {}

  for _, resource_data in pairs(resource_data_by_resource_name) do
    local category = resource_data.category
    local required_fluid = resource_data.required_fluid

    for mining_drill_name, drill_data in pairs(drill_index[category]) do
      if is_fluid then
        if not drill_data.can_mine_fluid then goto next_drill end
        local filter = drill_data.output_filter
        if filter and filter ~= item_name then goto next_drill end
      end
      if required_fluid then
        if not drill_data.can_apply_fluid then goto next_drill end
        local filter = drill_data.input_filter
        if filter and filter ~= required_fluid then goto next_drill end
      end
      -- yay! drill can mine resource, add it to the list.
      mining_drills[mining_drill_name] = true
      ::next_drill::
    end
  end

  local F_drill_placeable_by = F.drill_placeable_by
  local F_items_that_place = F.items_that_place

  local found_items = {}

  for mining_drill_name in pairs(mining_drills) do
    local drill_placeable_by=F_drill_placeable_by[mining_drill_name]
    if drill_placeable_by then
      for drill_item_name in pairs(drill_placeable_by) do
        found_items[drill_item_name] = true
      end
    end
    local items_that_place = F_items_that_place[mining_drill_name]
    if items_that_place then
      for drill_item_name in pairs(items_that_place) do
        found_items[drill_item_name] = true
      end
    end
  end

  for drill_item_name in pairs(found_items) do
    local temp = {
      name = drill_item_name,
      type = 'item'
    }
    item_names[temp] = bor(item_names[temp] or 0, difficulties)
  end

  return false
end

local function register_new_item(item, item_name, _, is_refresh)
  local F_items_that_place = F.items_that_place
  if is_refresh then
    for _, items in pairs(F_items_that_place) do
      items[item_name] = nil
    end
  end
  local entity_name = item.place_result
  if not entity_name then return end

  autovivify(F_items_that_place, entity_name)[item_name] = true
end

local function register_new_mining_drill(mining_drill, mining_drill_name, _, is_refresh)
  if is_refresh then
    for _, drills in pairs(F.drill_index) do
      drills[mining_drill_name] = nil
    end
    F.drill_placeable_by[mining_drill_name] = nil
  end

  local placeable_by = mining_drill.placeable_by
  if placeable_by then
    if type(placeable_by) == 'string' then
      F.drill_placeable_by[mining_drill_name] = { placeable_by }
    else
      F.drill_placeable_by[mining_drill_name] = placeable_by
    end
  end

  local mining_drill_data = {}

  local output_fluid_box = mining_drill.output_fluid_box
  if output_fluid_box then
    mining_drill_data.can_mine_fluid = true
    local filter = output_fluid_box.filter
    if filter then
      mining_drill_data.output_fluid = filter
    end
  end

  local input_fluid_box = mining_drill.input_fluid_box
  if input_fluid_box then
    mining_drill_data.can_apply_fluid = true
    local filter = input_fluid_box.filter
    if filter then
      mining_drill_data.input_fluid = filter
    end
  end

  local resource_categories = mining_drill.resource_categories
  for i = 1,#resource_categories do
    local resource_category_name = resource_categories[i]
    autovivify(F.drill_index, resource_category_name)[mining_drill_name] = mining_drill_data
  end
end

local function register_new_resource(resource, resource_name, _, is_refresh)
  local F_resource_data_by_type_and_item = F.resource_data_by_type_and_item
  if is_refresh then
    for _, type_data in pairs(F_resource_data_by_type_and_item) do
      for _, resource_data in pairs(type_data) do
        resource_data[resource_name] = nil
      end
    end
  end

  local autoplace = resource.autoplace
  if not autoplace then return end

  local minable = resource.minable
  if not minable then return end

  local resource_data = {
    category = resource.category or "basic-solid",
    required_fluid = minable.required_fluid
  }

  local results = minable.results
  if results then
    if #results == 0 then return end
    for i = 1,#results do
      local result = results[i]
      autovivify(autovivify(F_resource_data_by_type_and_item, result.type or 'item'), result.name or result[1])[resource_name] = resource_data
    end
  else
    local result = minable.result
    if not result then return end
    autovivify(autovivify(F_resource_data_by_type_and_item,'item'),result)[resource_name] = resource_data
  end
end

local function catalog_technology(technology_name, technology_data, flags)
  local recipe_name_to_technology_names = F.recipe_name_to_technology_names
  local technology_name_to_dependent_technology_names = F.technology_name_to_dependent_technology_names
  local technology_name_to_prerequisite_technology_names = F.technology_name_to_prerequisite_technology_names
  local effects = technology_data.effects
  if effects then
    for _,effect in ipairs(effects) do
      if effect.type == "unlock-recipe" then
        local recipe_name = effect.recipe
        local technology_names = autovivify(recipe_name_to_technology_names,recipe_name)
        technology_names[technology_name] = bor(technology_names[technology_name] or 0, flags)
      end
    end
  end
  local prerequisites = technology_data.prerequisites
  if prerequisites then
    local prerequiste_technology_names = autovivify(technology_name_to_prerequisite_technology_names, technology_name)
    for _, prerequisite_name in ipairs(prerequisites) do
      local dependent_technology_names = autovivify(technology_name_to_dependent_technology_names, prerequisite_name)
      dependent_technology_names[technology_name] = bor(dependent_technology_names[technology_name] or 0, flags)
      prerequiste_technology_names[prerequisite_name] = bor(prerequiste_technology_names[prerequisite_name] or 0, flags)
    end
  end
end

local function register_new_technology(technology, technology_name, _, is_refresh)
  if technology_name:sub(1,9) == 'OR-Nodes-' then return end
  if is_refresh then
    for _, technology_names in pairs(F.recipe_name_to_technology_names) do
      technology_names[technology_name] = nil
    end
    for _, technology_names in pairs(F.technology_name_to_dependent_technology_names) do
      technology_names[technology_name] = nil
    end
  end
  local expensive = technology.expensive
  local normal = technology.normal
  -- https://wiki.factorio.com/Prototype/Technology#Technology_data
  if expensive or normal then
    if not expensive then
      catalog_technology(technology_name, normal, 3 --[[DIFFICULTY_BOTH]])
    elseif not normal then
      catalog_technology(technology_name, expensive, 3 --[[DIFFICULTY_BOTH]])
    else
      catalog_technology(technology_name, normal, 1 --[[DIFFICULTY_NORMAL]])
      catalog_technology(technology_name, expensive, 2 --[[DIFFICULTY_EXPENSIVE]])
    end
  else
    catalog_technology(technology_name, technology, 3 --[[DIFFICULTY_BOTH]])
  end
end

local function collect_technologies_for_recipe(technology_names, recipe_name, recipe_flags)
  local recipe_data = F.recipe_name_to_technology_names[recipe_name]
  if not recipe_data then return false end

  for technology_name, flags in pairs(recipe_data) do
    technology_names[technology_name] = bor(technology_names[technology_name] or 0, band(flags, recipe_flags))
  end
  return true
end

--[[
input dependency: a | c
tree: a -> b -> c
output dependency: c
]]
local function simplify_technologies(technology_set)
  local technology_name_to_dependent_technology_names = F.technology_name_to_dependent_technology_names
  for base_technology_name, base_difficulties in pairs(table.deepcopy(technology_set)) do
    local queue = { { base_technology_name, base_difficulties } }
    local seen = {}
    for _, head in pairs(queue) do
      local technology_name = head[1]
      local difficulties = head[2]
      local dependent_technology_names = technology_name_to_dependent_technology_names[technology_name]
      if not dependent_technology_names then goto next end
      for dependent_technology_name, dependency_difficulties in pairs(dependent_technology_names) do
        if not seen[dependent_technology_name] then
          local foo = technology_set[dependent_technology_name]
          if foo then
            -- foo = foo - dependency_difficulties
            foo = band(foo, bnot(dependency_difficulties))
            if foo == 0 then
              technology_set[dependent_technology_name] = nil
            else
              technology_set[dependent_technology_name] = foo
            end
          end
          seen[dependent_technology_name] = true
          dependency_difficulties = band(difficulties, dependency_difficulties)
          if dependency_difficulties ~= 0 then
            queue[#queue+1] = { dependent_technology_name, dependency_difficulties }
          end
        end
      end
      ::next::
    end
  end
end

--[[
input dependency: a & c
tree: a -> b -> c
output dependency: a
]]
local simplify_technologies2_done = nil -- TODO
local function simplify_technologies2(technology_set)
  if not simplify_technologies2_done then return end
  local technology_name_to_prerequisite_technology_names = F.technology_name_to_prerequisite_technology_names
  for base_technology_name, base_difficulties in pairs(table.deepcopy(technology_set)) do
    local queue = { { base_technology_name, base_difficulties } }
    local seen = {}
    for _, head in pairs(queue) do
      local technology_name = head[1]
      local difficulties = head[2]
      local prerequisite_technology_names = technology_name_to_prerequisite_technology_names[technology_name]
      if not prerequisite_technology_names then goto next end
      for prerequisite_technology_name, dependency_difficulties in pairs(prerequisite_technology_names) do
        if not seen[prerequisite_technology_name] then
          local foo = technology_set[prerequisite_technology_name]
          if foo then
            -- foo = foo - dependency_difficulties
            foo = band(foo, bnot(dependency_difficulties))
            if foo == 0 then
              technology_set[prerequisite_technology_name] = nil
            else
              technology_set[prerequisite_technology_name] = foo
            end
          end
          seen[prerequisite_technology_name] = true
          dependency_difficulties = band(difficulties, dependency_difficulties)
          if dependency_difficulties ~= 0 then
            queue[#queue+1] = { prerequisite_technology_name, dependency_difficulties }
          end
        end
      end
      ::next::
    end
  end
end

local function catalog_result(recipe_name, ingredient_name, ingredient_type, recipe_flags)
  local recipe_index = F.recipe_index
  local type_data = autovivify(recipe_index,ingredient_type)
  local ingredient_data = autovivify(type_data,ingredient_name)
  ingredient_data[recipe_name] = bor(ingredient_data[recipe_name] or 0, recipe_flags)
end

local function catalog_recipe(recipe_name, recipe_data, disabled, recipe_flags)
  local result_name = recipe_data.result
  if not disabled then
    local enabled = recipe_data.enabled
    if enabled ~= false then
      -- enabled_at_start is 2 bits to the left of the difficulty flags.
      recipe_flags = bor(recipe_flags, lshift(recipe_flags, 2))
    end
  end
  if result_name then
    return catalog_result(recipe_name, result_name, 'item', recipe_flags)
  else
    local results = recipe_data.results
    if not results then return end
    for _,result in ipairs(results) do
      local result_type = result.type
      if result_type then
        catalog_result(recipe_name, result.name, result_type, recipe_flags)
      else
        catalog_result(recipe_name, result.name or result[1], 'item', recipe_flags)
      end
    end
  end
end

local function register_new_recipe(recipe, recipe_name, _, is_refresh)
  if is_refresh then
    for _, type_data in pairs(F.recipe_index) do
      for _, ingredient_data in pairs(type_data) do
        ingredient_data[recipe_name] = nil
      end
    end
  end
  -- https://wiki.factorio.com/Prototype/Recipe#Recipe_data
  local expensive = recipe.expensive
  local normal = recipe.normal
  if expensive or normal then
    if expensive == false then
      catalog_recipe(recipe_name, normal, false, 1 --[[DIFFICULTY_NORMAL]])
      catalog_recipe(recipe_name, normal, true, 2 --[[DIFFICULTY_EXPENSIVE]])
    elseif normal == false then
      catalog_recipe(recipe_name, expensive, false, 2 --[[DIFFICULTY_EXPENSIVE]])
      catalog_recipe(recipe_name, expensive, true, 1 --[[DIFFICULTY_NORMAL]])
    elseif expensive == nil then
      catalog_recipe(recipe_name, normal, false, 3 --[[DIFFICULTY_BOTH]])
    elseif normal == nil then
      catalog_recipe(recipe_name, expensive, false, 3 --[[DIFFICULTY_BOTH]])
    else
      catalog_recipe(recipe_name, normal, false, 1 --[[DIFFICULTY_NORMAL]])
      catalog_recipe(recipe_name, expensive, false, 2 --[[DIFFICULTY_EXPENSIVE]])
    end
  else
    catalog_recipe(recipe_name, recipe, false, 3 --[[DIFFICULTY_BOTH]])
  end
end

local function collect_recipes_for_item(recipes, item, difficulties)
  local item_name = item.name
  local item_type = item.type
  difficulties = difficulties or 3
  local item_mask = bor(difficulties, lshift(difficulties,2))
  if item_type ~= 'fluid' then
    item_type = 'item'
  end
  local type_data = F.recipe_index[item_type]
  if not type_data then return end
  local item_data = type_data[item_name]
  if not item_data then return end
  for recipe_name, recipe_data in pairs(item_data) do
    recipes[recipe_name] = bor(recipes[recipe_name] or 0, band(recipe_data, item_mask))
  end
  return true
end

local function get_technology_enabled_flags(technology)
  local expensive = technology.expensive
  local normal = technology.normal
  -- https://wiki.factorio.com/Prototype/Recipe#Recipe_data
  if expensive or normal then
    if expensive == false then
      if normal.enabled ~= false then
        return 1 --[[DIFFICULTY_NORMAL]]
      end
      return 0
    elseif normal == false then
      if expensive.enabled ~= false then
        return 2 --[[DIFFICULTY_EXPENSIVE]]
      end
      return 0
    elseif expensive == nil then
      if normal.enabled ~= false then
        return 3 --[[DIFFICULTY_BOTH]]
      end
      return 0
    elseif normal == nil then
      if expensive.enabled ~= false then
        return 3 --[[DIFFICULTY_BOTH]]
      end
      return 0
    else
      local flags = 0
      if normal.enabled ~= false then flags = flags + 4 end
      if expensive.enabled ~= false then flags = flags + 8 end
      return flags
    end
  else
    if technology.enabled ~= false then
      return 3 --[[DIFFICULTY_BOTH]]
    end
    return 0
  end
end

local function get_recipe_enabled_flags(recipe)
  local expensive = recipe.expensive
  local normal = recipe.normal
  -- https://wiki.factorio.com/Prototype/Recipe#Recipe_data
  if expensive or normal then
    if expensive == false then
      if normal.enabled ~= false then
        return 4 --[[AVAILABLE_BY_DEFAULT_NORMAL]]
      end
      return 0
    elseif normal == false then
      if expensive.enabled ~= false then
        return 8 --[[AVAILABLE_BY_DEFAULT_EXPENSIVE]]
      end
      return 0
    elseif expensive == nil then
      if normal.enabled ~= false then
        return 12 --[[AVAILABLE_BY_DEFAULT_BOTH]]
      end
      return 0
    elseif normal == nil then
      if expensive.enabled ~= false then
        return 12 --[[AVAILABLE_BY_DEFAULT_BOTH]]
      end
      return 0
    else
      local flags = 0
      if normal.enabled ~= false then flags = flags + 4 end
      if expensive.enabled ~= false then flags = flags + 8 end
      return flags
    end
  else
    if recipe.enabled ~= false then
      return 12 --[[AVAILABLE_BY_DEFAULT_BOTH]]
    end
    return 0
  end
end

local function compose_icons(icons)
  local temp = {
    {
      icon = OR_ICON,
      icon_size = 128,
    }
  }
  local scale = 1 / (#icons)
  local scale4 = 4 * scale
  local offset = (64 * scale) - 64
  for i,source_icons in ipairs(icons) do
    temp = util.combine_icons(
      temp,
      source_icons,
      {
        scale = scale4,
        shift = { offset, (((i - 0.5) * scale) * 128) - 64 }
      }
    )
  end
  return temp
end

local compose_names_lookup = {
  nil,
  "OR-Nodes.list-2",
  "OR-Nodes.list-3",
  "OR-Nodes.list-4",
  "OR-Nodes.list-5"
}

local compose_names_lookup2 = {
  nil,
  "OR-Nodes.and-list-2",
  "OR-Nodes.and-list-3",
  "OR-Nodes.and-list-4",
  "OR-Nodes.and-list-5"
}

local function compose_names(names, and_mode)
  local list
  if and_mode then
    list = compose_names_lookup2[#names]
  else
    list = compose_names_lookup[#names]
  end
  local result
  if list then
    result = {list}
    for _, name in ipairs(names) do
      result[#result+1] = name.name
    end
    return result
  else
    if and_mode then
      result = {"OR-Nodes.and-list-6+"}
    else
      result = {"OR-Nodes.list-6+"}
    end
    for i = 1, 4 do
      result[i+1] = names[i].name
    end
    result[6] = names[#names].name
  end
  return result
end

local derive_name

if mods['HighlyDerivative'] then
  derive_name = HighlyDerivative.derive_name
else
  local DerivedNames = {}
  local NameColission = {}

  local MAX_NAME_LENGTH = 200
  local DOTS_LENGTH = string.len("…") -- 3
  local MAX_OFFSET = math.pow(2,53) -- 9.0x10^15
  local MAX_OFFSET_LENGTH = math.ceil(math.log10(MAX_OFFSET)) -- 16
  local HASH_LENGTH = 8 -- uint32 0xFFFFFFFF
  -- name = concat(prefix, '-', hash, '-', offset '-', names, "…")
  local MAX_PREFIX_LENGTH = MAX_NAME_LENGTH - HASH_LENGTH - MAX_OFFSET_LENGTH - DOTS_LENGTH - 3 --[[ x '-' ]]

  function derive_name(prefix, ...)
    local components = { ... }
    local prefix_len = prefix:len()
    if prefix_len > MAX_PREFIX_LENGTH then
      error("Cannot produce a valid prototype name including prefix if prefix is greater than " .. MAX_PREFIX_LENGTH .. " characters in length.")
    end
    components = table.concat(components, '-')
    if components:len() + prefix_len < 200 then return prefix .. components end
    local prefix_names = DerivedNames[prefix]
    local new_name
    if prefix_names then
      new_name = prefix_names[components]
      if new_name then return new_name end
    else
      prefix_names = {}
      DerivedNames[prefix] = prefix_names
    end
    local ingredients_hash = hash(components)
    new_name = (prefix .. ingredients_hash .. components):sub(1,197) .. "…"
    local offset = NameColission[new_name]
    if not offset then
      NameColission[new_name] = 0
      prefix_names[components] = new_name
      return new_name
    end
    if offset >= MAX_OFFSET then
      error("Cannot create a unique name, too many collisions")
    end
    NameColission[new_name] = offset + 1
    return (prefix .. ingredients_hash .. '-' .. offset .. '-' .. components):sub(1,197) .. "…"
  end
end







------------------------------------------------------------------------
-- Actual technology creation.

local function create_or_node(node_data, _, _)
  local new_technologies = F.new_technologies
  local target_name = node_data.target_name
  local old_technology = new_technologies[target_name]
  if old_technology then return { old_technology } end

  local name_type = node_data.name_type

  local mode = node_data.mode
  local and_mode = false
  if mode and mode == 'and' then and_mode = true end

  local short_tech_name
  if and_mode then
    short_tech_name = derive_name(PREFIX_AND, name_type, target_name)
  else
    short_tech_name = derive_name(PREFIX_OR, name_type, target_name)
  end
  new_technologies[target_name] = short_tech_name

  local icons = node_data.icons
  local icon = node_data.icon

  -- TODO AND_ICON
  if icons then
    icons = compose_icons(icons)
  elseif icon then
    icons = icon
  else
    icons = {
      {
        icon = OR_ICON,
        icon_size = 128,
      }
    }
  end

  local names = node_data.names
  local name = node_data.name
  if names and #names == 1 then
    name = names[1]
  end

  local localised_name
  local localised_description

  if name then
    localised_name = name.name
    if name_type == 'items' then
      localised_description = {"OR-Nodes-description.item-craftable", localised_name}
    elseif name_type == 'recipes' then
      localised_description = {"OR-Nodes-description.recipe-craftable", localised_name}
    end
  elseif names then
    if and_mode then
      localised_name = {"OR-Nodes-name.and-node-name", F.unnamed_and_node_count}
      F.unnamed_and_node_count = F.unnamed_and_node_count + 1
    else
      localised_name = {"OR-Nodes-name.node-name", F.unnamed_or_node_count}
      F.unnamed_or_node_count = F.unnamed_or_node_count + 1
    end
    localised_description = compose_names(names, and_mode)
    if name_type == 'items' then
      if and_mode then
        localised_description = {"OR-Nodes-description.items-all-craftable", localised_description}
      else
        localised_description = {"OR-Nodes-description.items-craftable", localised_description}
      end
    elseif name_type == 'recipes' then
      if and_mode then
        localised_description = {"OR-Nodes-description.recipes-all-craftable", localised_description}
      else
        localised_description = {"OR-Nodes-description.recipes-craftable", localised_description}
      end
    elseif name_type == 'technologies' then
      if and_mode then
        localised_description = {"OR-Nodes-description.technologies-all-researched", localised_description}
      else
        localised_description = {"OR-Nodes-description.technologies-researched", localised_description}
      end
    end
  end

  local technology = {
    type = "technology",
    name = short_tech_name,
    icons = icons,
    localised_name = localised_name,
    localised_description = localised_description,
  }

  local technology_data = {
    visible_when_disabled = false,
    unit = {
      count = 1,
      ingredients = {},
      time = 1/60
    },
    prerequisites = nil
  }

  local technology_names = node_data.technology_names

  local prerequisites = {}
  local normal_prerequisites = {}
  local expensive_prerequisites = {}

  for technology_name, difficulties in pairs(technology_names) do
    if band(difficulties,3 --[[DIFFICULTY_BOTH]]) == 3 --[[DIFFICULTY_BOTH]] then
      prerequisites[#prerequisites+1] = technology_name
    elseif band(difficulties,1 --[[DIFFICULTY_NORMAL]]) == 1 --[[DIFFICULTY_NORMAL]] then
      normal_prerequisites[#normal_prerequisites+1] = technology_name
    elseif band(difficulties,2 --[[DIFFICULTY_EXPENSIVE]]) == 2 --[[DIFFICULTY_EXPENSIVE]] then
      expensive_prerequisites[#expensive_prerequisites+1] = technology_name
    end
  end

  if next(normal_prerequisites) or next(expensive_prerequisites) then
    for _, technology_name in pairs(prerequisites) do
      normal_prerequisites[#normal_prerequisites+1] = technology_name
      expensive_prerequisites[#expensive_prerequisites+1] = technology_name
    end
    if not next(normal_prerequisites) then
      technology_data.prerequisites = expensive_prerequisites
      technology.expensive = technology_data
      technology.normal = false
    elseif not next(expensive_prerequisites) then
      technology_data.prerequisites = normal_prerequisites
      technology.normal = technology_data
      technology.expensive = false
    else
      local expensive_data = table.deepcopy(technology_data)
      local normal_data = technology_data
      expensive_data.prerequisites = expensive_prerequisites
      normal_data.prerequisites = normal_prerequisites
      technology.normal = normal_data
      technology.expensive = expensive_data
      end
  else
    technology_data.prerequisites = prerequisites
    technology.normal = technology_data
  end

  log(serpent.block(technology))

  data:extend{ technology }

  if HighlyDerivative then HighlyDerivative.index(technology) end

  return { short_tech_name }
end





-------------------------------------------------------------------------
-- wrapper functions

local function foobarbaz(node_data, levels, is_silent)
  levels = levels + 1
  local recipe_names = node_data.recipe_names or {}
  local technology_names = node_data.technology_names or {}

  local items = node_data.item_names
  if items then
    local items_to_mine = {}
    while next(items) do
      for item, difficulties in pairs (items) do
        --if item_can_be_mined_from_start(item) then return {} end
        collect_recipes_for_item(recipe_names, item, difficulties)
        collect_items_to_mine_item(items_to_mine, item, difficulties)
      end
      items = items_to_mine
      items_to_mine = {}
    end
    if not next(recipe_names) and not next(technology_names) then
      return report_error(is_silent, levels + 1, 'No required items could be crafted or mined.')
    end
  end

  local combined_recipe_flags = 0
  for recipe_name, recipe_flags in pairs(recipe_names) do
    combined_recipe_flags = bor(combined_recipe_flags, recipe_flags)
    if band(combined_recipe_flags, 12 --[[AVAILABLE_BY_DEFAULT_MASK]]) == 12 --[[AVAILABLE_BY_DEFAULT_BOTH]] then
      -- at least one recipe is able to be crafted for normal and for expensive from game start, thus the condition is satisfied from game start.
      return {}
    end
    collect_technologies_for_recipe(technology_names, recipe_name, recipe_flags)
  end

  simplify_technologies(technology_names)

  local technology_name, technology_flags = next(technology_names)
  if not technology_name then
    return {}
  end
  if next(technology_names, technology_name) then
    node_data.technology_names = technology_names
    return create_or_node(node_data, levels + 1, is_silent)
  end
  -- TODO what if technology was not requested on all difficulties?
  if band(technology_flags, 3 --[[DIFFICULTY_MASK]]) ~= 3 --[[DIFFICULTY_BOTH]] then
    return report_error(is_silent, levels + 1, 'The technology found does not exist on all difficulty levels')
  end
  return { technology_name }
end

local function foobarbaz_and(node_data, levels, is_silent)
  levels = levels + 1
  local technology_names = node_data.technology_names

  simplify_technologies2(technology_names)

  local technology_name, technology_flags = next(technology_names)
  if not technology_name then
    return {}
  end
  if next(technology_names, technology_name) then
    node_data.technology_names = technology_names
    return create_or_node(node_data, levels + 1, is_silent)
  end
  -- TODO what if technology was not requested on all difficulties?
  if band(technology_flags, 3 --[[DIFFICULTY_MASK]]) ~= 3 --[[DIFFICULTY_BOTH]] then
    return report_error(is_silent, levels + 1, 'The technology found does not exist on all difficulty levels')
  end
  return { technology_name }
end






--------------------------------------------------------------------------
-- public functions

function F.depend_on_all_recipe_ingredients(recipe, is_silent)
  local levels = 1
  if not recipe then
    return report_error(is_silent, 1, "Please supply a recipe_name or recipe prototype.")
  end

  local recipe_name
  if type(recipe) == 'table' then
    recipe_name = recipe.name
    if not recipe_name then
      return report_error(is_silent, 1, "Supplied recipe prototype does not have a name")
    end
  else
    recipe_name = recipe
    recipe = find_prototype(recipe_name, 'recipe', is_silent)
    if not recipe then
      return report_error(is_silent, 1, "Could not find a recipe with the supplied name")
    end
  end

  -- ingredients[fluid/item][name] = difficulties
  local temp_ingredients = {}

  local has_ingredients = false

  local function collect_ingredients(recipe_data, flags)
    local recipe_ingredients = recipe_data.ingredients
    for i = 1,#recipe_ingredients do
      has_ingredients = true
      local ingredient = recipe_ingredients[i]
      local ingredient_type = ingredient.type or 'item'
      local type_ingredients = autovivify(temp_ingredients, ingredient_type)
      local ingredient_name
      if ingredient_type == 'fluid' then
        ingredient_name = ingredient.name
      else
        ingredient_name = ingredient.name or ingredient[1]
      end
      type_ingredients[ingredient_name] = bor(type_ingredients[ingredient_name] or 0, flags)
    end
  end

  local normal = recipe.normal
  local expensive = recipe.expensive

  if expensive or normal then
    if not expensive then
      collect_ingredients(normal, 3 --[[DIFFICULTY_BOTH]])
    elseif not normal then
      collect_ingredients(expensive, 3 --[[DIFFICULTY_BOTH]])
    else
      collect_ingredients(normal, 1 --[[DIFFICULTY_NORMAL]])
      collect_ingredients(expensive, 2 --[[DIFFICULTY_EXPENSIVE]])
    end
  else
    collect_ingredients(recipe, 3 --[[DIFFICULTY_BOTH]])
  end

  if not has_ingredients then return {} end

  local found_technology_names = {}

  for ingredient_type, type_ingredients in pairs(temp_ingredients) do
    for ingredient_name, difficulties in pairs(type_ingredients) do
      local item = find_prototype(ingredient_name, ingredient_type, true)
      if not item then
        return report_error(is_silent, levels, 'One of the ingredients was not found.')
      end
      local technology = foobarbaz(
        {
          target_name = ingredient_type .. '-' .. ingredient_name,
          name_type = 'item',
          item_names = {
            [item] = 3
          },
          icon = icons_of(item),
          name = locale_of(item),
        },
        levels,
        is_silent
      )
      if not technology then return nil end
      local technology_name = technology[1]
      if not technology_name then goto next_ingredient end
      found_technology_names[technology_name] = bor(
        found_technology_names[technology_name] or 0,
        band(get_technology_enabled_flags(technology), difficulties)
      )
      ::next_ingredient::
    end
  end

  local technology_name, technology_flags = next(found_technology_names)
  if not technology_name then return {} end
  if next(found_technology_names, technology_name) then
    return foobarbaz_and(
      {
        target_name = recipe_name,
        name_type = 'recipe',
        technology_names = found_technology_names,
        name = locale_of(recipe),
        icon = icons_of(recipe),
        mode = 'and'
      },
      1,
      is_silent
    )
  end
  -- TODO what if the item required and technology exist only in one difficulty?
  if band(technology_flags, 3 --[[DIFFICULTY_MASK]]) ~= 3 --[[DIFFICULTY_BOTH]] then
    return report_error(is_silent, 1, 'The technology found does not exist on all difficulty levels')
  end
  return { technology_name }
end

-- begin generated functions
function F.depend_on_all_technologies(technology_names, is_silent)
  local levels = 1
  if not technology_names or not type(technology_names) == "table" then
    return report_error(is_silent, levels, "Please supply a list of technology names.")
  end

  local target_names = {}
  local found_technology_names = {}
  local icons = {}
  local names = {}
  local has_technologies = false

  for technology_name, difficulties in pairs(technology_names) do
    if type(technology_name) == 'number' then
      technology_name = difficulties
      difficulties = 3 --[[DIFFICULTIES_BOTH]]
    end
    if band(difficulties, 3 --[[DIFFICULTIES_MASK]]) == 0 then goto next_technology end
    if not type(technology_name) == 'string' then
      return report_error(is_silent, levels, "One of the supplied technology names was not a string")
    end
    has_technologies = true
    local technology = find_prototype(technology_name, 'technology', true)
    if not technology then
      return report_error(is_silent, levels, 'One of the technologies was not found.')
    end
    local target_name = technology_name
    local icon = icons_of(technology)
    local name = locale_of(technology)
    if band(difficulties, 3) == 1 --[[DIFFICULTY_NORMAL]] then
      target_name = target_name .. '-normal'
    elseif band(difficulties, 3) == 2 --[[DIFFICULTY_EXPENSIVE]] then
      target_name = target_name .. '-expensive'
    else -- DIFFICULTY_BOTH
      target_name = target_name
    end
    if not names[target_name] then
      target_names[#target_names + 1] = target_name
      names[target_name] = name
      icons[target_name] = icon
    end

    if not technology_name then goto next_technology end
    found_technology_names[technology_name] = bor(found_technology_names[technology_name] or 0, band(get_technology_enabled_flags(technology), difficulties))
    ::next_technology::
  end

  if not has_technologies then return {} end

  table.sort(target_names)

  for i = 1,#target_names do
    local target_name = target_names[i]
    icons[i] = icons[target_name]
    names[i] = names[target_name]
    icons[target_name] = nil
    names[target_name] = nil
  end

  return foobarbaz_and(
    {
      target_name = table.concat(target_names, '-and-'),
      name_type = 'technologies',
      technology_names = found_technology_names,
      mode = 'and',
      icons = icons,
      names = names
    },
    levels,
    is_silent
  )
end

function F.depend_on_any_technology(technology_names, is_silent)
  local levels = 1
  if not technology_names or not type(technology_names) == "table" then
    return report_error(is_silent, levels, "Please supply a list of technology names.")
  end

  local target_names = {}
  local found_technology_names = {}
  local icons = {}
  local names = {}
  local has_technologies = false

  for technology_name, difficulties in pairs(technology_names) do
    if type(technology_name) == 'number' then
      technology_name = difficulties
      difficulties = 3 --[[DIFFICULTIES_BOTH]]
    end
    if band(difficulties, 3 --[[DIFFICULTIES_MASK]]) == 0 then goto next_technology end
    if not type(technology_name) == 'string' then
      return report_error(is_silent, levels, "One of the supplied technology names was not a string")
    end
    has_technologies = true
    local technology = find_prototype(technology_name, 'technology', true)
    if not technology then goto next_technology end
    local target_name = technology_name
    if not names[target_name] then
      target_names[#target_names + 1] = target_name
      icons[target_name] = icons_of(technology)
      names[target_name] = locale_of(technology)
    end
    found_technology_names[technology_name] = bor(found_technology_names[technology_name] or 0,
      band(get_technology_enabled_flags(technology), difficulties)
    )
    ::next_technology::
  end

  if not has_technologies then return {} end

  if #target_names == 0 then
    return report_error(is_silent, levels, 'None of the technologies were found.')
  end

  table.sort(target_names)

  for i = 1,#target_names do
    local target_name = target_names[i]
    icons[i] = icons[target_name]
    names[i] = names[target_name]
    icons[target_name] = nil
    names[target_name] = nil
  end

  return foobarbaz(
    {
      target_name = table.concat(target_names, '-or-'),
      name_type = 'technologies',
      technology_names = found_technology_names,
      icons = icons,
      names = names
    },
    levels,
    is_silent
  )
end

function F.depend_on_all_recipes(recipe_names, is_silent)
  local levels = 1
  if not recipe_names or not type(recipe_names) == "table" then
    return report_error(is_silent, levels, "Please supply a list of recipe names.")
  end

  local target_names = {}
  local found_technology_names = {}
  local icons = {}
  local names = {}
  local has_recipes = false

  for recipe_name, difficulties in pairs(recipe_names) do
    if type(recipe_name) == 'number' then
      recipe_name = difficulties
      difficulties = 3 --[[DIFFICULTIES_BOTH]]
    end
    if band(difficulties, 3 --[[DIFFICULTIES_MASK]]) == 0 then goto next_recipe end
    if not type(recipe_name) == 'string' then
      return report_error(is_silent, levels, "One of the supplied recipe names was not a string")
    end
    has_recipes = true
    local recipe = find_prototype(recipe_name, 'recipe', true)
    if not recipe then
      return report_error(is_silent, levels, 'One of the recipes was not found.')
    end
    local target_name = recipe_name
    local icon = icons_of(recipe)
    local name = locale_of(recipe)
    local technology = foobarbaz(
      {
        target_name = target_name,
        name_type = 'recipe',
        recipe_names = {
          [recipe_name] = 3 --[[DIFFICULTY_BOTH]]
        },
        icon = icon,
        name = name,
      },
      levels,
      is_silent
    )
    if not technology then return nil end
    if band(difficulties, 3) == 1 --[[DIFFICULTY_NORMAL]] then
      target_name = target_name .. '-normal'
    elseif band(difficulties, 3) == 2 --[[DIFFICULTY_EXPENSIVE]] then
      target_name = target_name .. '-expensive'
    else -- DIFFICULTY_BOTH
      target_name = target_name
    end
    if not names[target_name] then
      target_names[#target_names + 1] = target_name
      names[target_name] = name
      icons[target_name] = icon
    end

    local technology_name = technology[1]
    if not technology_name then goto next_recipe end
    found_technology_names[technology_name] = bor(found_technology_names[technology_name] or 0, band(get_technology_enabled_flags(technology), difficulties))
    ::next_recipe::
  end

  if not has_recipes then return {} end

  table.sort(target_names)

  for i = 1,#target_names do
    local target_name = target_names[i]
    icons[i] = icons[target_name]
    names[i] = names[target_name]
    icons[target_name] = nil
    names[target_name] = nil
  end

  return foobarbaz_and(
    {
      target_name = table.concat(target_names, '-and-'),
      name_type = 'recipes',
      technology_names = found_technology_names,
      mode = 'and',
      icons = icons,
      names = names
    },
    levels,
    is_silent
  )
end

local function _depend_on_any_recipe(recipe_names, is_silent, levels)
  levels = levels + 1
  if not recipe_names or not type(recipe_names) == "table" then
    return report_error(is_silent, levels, "Please supply a list of recipe names.")
  end

  local target_names = {}
  local found_recipe_names = {}
  local icons = {}
  local names = {}
  local has_recipes = false

  for recipe_name, difficulties in pairs(recipe_names) do
    if type(recipe_name) == 'number' then
      recipe_name = difficulties
      difficulties = 3 --[[DIFFICULTIES_BOTH]]
    end
    if band(difficulties, 3 --[[DIFFICULTIES_MASK]]) == 0 then goto next_recipe end
    if not type(recipe_name) == 'string' then
      return report_error(is_silent, levels, "One of the supplied recipe names was not a string")
    end
    has_recipes = true
    local recipe = find_prototype(recipe_name, 'recipe', true)
    if not recipe then goto next_recipe end
    local target_name = recipe_name
    if not names[target_name] then
      target_names[#target_names + 1] = target_name
      icons[target_name] = icons_of(recipe)
      names[target_name] = locale_of(recipe)
    end
    local recipe_mask = lshift(difficulties,2)
    found_recipe_names[recipe_name] = bor(found_recipe_names[recipe_name] or 0,
      bor(band(get_recipe_enabled_flags(recipe), recipe_mask), difficulties)
    )
    ::next_recipe::
  end

  if not has_recipes then return {} end

  if #target_names == 0 then
    return report_error(is_silent, levels, 'None of the recipes were found.')
  end

  table.sort(target_names)

  for i = 1,#target_names do
    local target_name = target_names[i]
    icons[i] = icons[target_name]
    names[i] = names[target_name]
    icons[target_name] = nil
    names[target_name] = nil
  end

  return foobarbaz(
    {
      target_name = table.concat(target_names, '-or-'),
      name_type = 'recipes',
      recipe_names = found_recipe_names,
      icons = icons,
      names = names
    },
    levels,
    is_silent
  )
end

function F.depend_on_any_recipe(recipe_names, is_silent)
  return _depend_on_any_recipe(recipe_names, is_silent, 1)
end

function F.depend_on_all_items(item_names, is_silent)
  local levels = 1
  if not item_names or not type(item_names) == "table" then
    return report_error(is_silent, levels, "Please supply a list of item names.")
  end

  local target_names = {}
  local found_technology_names = {}
  local icons = {}
  local names = {}
  local has_items = false

  for item_name, difficulties in pairs(item_names) do
    if type(item_name) == 'number' then
      item_name = difficulties
      difficulties = 3 --[[DIFFICULTIES_BOTH]]
    end
    if band(difficulties, 3 --[[DIFFICULTIES_MASK]]) == 0 then goto next_item end
    local ingredient_data_type = type(item_name)
    local ingredient_name
    local ingredient_type
    if ingredient_data_type == 'string' then
      ingredient_name = item_name
      ingredient_type = 'item'
    elseif ingredient_data_type == 'table' then
      ingredient_name = item_name.name or item_name[1]
      ingredient_type = item_name.type or item_name[2] or 'item'
    else
      return report_error(is_silent, levels, "Supplied ingredient was neither an item name nor an ingredient prototype")
    end
    has_items = true
    local item = find_prototype(ingredient_name, ingredient_type, true)
    if not item then
      return report_error(is_silent, levels, 'One of the items was not found.')
    end
    local target_name = ingredient_type .. '-' .. ingredient_name
    local icon = icons_of(item)
    local name = locale_of(item)
    local technology = foobarbaz(
      {
        target_name = target_name,
        name_type = 'item',
        item_names = {
          [item] = 3 --[[DIFFICULTY_BOTH]]
        },
        icon = icon,
        name = name,
      },
      levels,
      is_silent
    )
    if not technology then return nil end
    if band(difficulties, 3) == 1 --[[DIFFICULTY_NORMAL]] then
      target_name = target_name .. '-normal'
    elseif band(difficulties, 3) == 2 --[[DIFFICULTY_EXPENSIVE]] then
      target_name = target_name .. '-expensive'
    else -- DIFFICULTY_BOTH
      target_name = target_name
    end
    if not names[target_name] then
      target_names[#target_names + 1] = target_name
      names[target_name] = name
      icons[target_name] = icon
    end

    local technology_name = technology[1]
    if not technology_name then goto next_item end
    found_technology_names[technology_name] = bor(found_technology_names[technology_name] or 0, band(get_technology_enabled_flags(technology), difficulties))
    ::next_item::
  end

  if not has_items then return {} end

  table.sort(target_names)

  for i = 1,#target_names do
    local target_name = target_names[i]
    icons[i] = icons[target_name]
    names[i] = names[target_name]
    icons[target_name] = nil
    names[target_name] = nil
  end

  return foobarbaz_and(
    {
      target_name = table.concat(target_names, '-and-'),
      name_type = 'items',
      technology_names = found_technology_names,
      mode = 'and',
      icons = icons,
      names = names
    },
    levels,
    is_silent
  )
end

local function _depend_on_any_item(item_names, is_silent, levels)
  levels = levels + 1
  if not item_names or not type(item_names) == "table" then
    return report_error(is_silent, levels, "Please supply a list of item names.")
  end

  local target_names = {}
  local found_item_names = {}
  local icons = {}
  local names = {}
  local has_items = false

  for item_name, difficulties in pairs(item_names) do
    if type(item_name) == 'number' then
      item_name = difficulties
      difficulties = 3 --[[DIFFICULTIES_BOTH]]
    end
    if band(difficulties, 3 --[[DIFFICULTIES_MASK]]) == 0 then goto next_item end
    local ingredient_data_type = type(item_name)
    local ingredient_name
    local ingredient_type
    if ingredient_data_type == 'string' then
      ingredient_name = item_name
      ingredient_type = 'item'
    elseif ingredient_data_type == 'table' then
      ingredient_name = item_name.name or item_name[1]
      ingredient_type = item_name.type or item_name[2] or 'item'
    else
      return report_error(is_silent, levels, "Supplied ingredient was neither an item name nor an ingredient prototype")
    end
    has_items = true
    local item = find_prototype(ingredient_name, ingredient_type, true)
    if not item then goto next_item end
    local target_name = ingredient_type .. '-' .. ingredient_name
    if not names[target_name] then
      target_names[#target_names + 1] = target_name
      icons[target_name] = icons_of(item)
      names[target_name] = locale_of(item)
    end
    found_item_names[item] = bor(found_item_names[item] or 0, difficulties)
    ::next_item::
  end

  if not has_items then return {} end

  if #target_names == 0 then
    return report_error(is_silent, levels, 'None of the items were found.')
  end

  table.sort(target_names)

  for i = 1,#target_names do
    local target_name = target_names[i]
    icons[i] = icons[target_name]
    names[i] = names[target_name]
    icons[target_name] = nil
    names[target_name] = nil
  end

  return foobarbaz(
    {
      target_name = table.concat(target_names, '-or-'),
      name_type = 'items',
      item_names = found_item_names,
      icons = icons,
      names = names
    },
    levels,
    is_silent
  )
end

function F.depend_on_any_item(item_names, is_silent)
  return _depend_on_any_item(item_names, is_silent, 1)
end

-- end generated functions

function F.depend_on_recipe(recipe_name, is_silent)
  return _depend_on_any_recipe({recipe_name}, is_silent, 1)
end

function F.depend_on_item(item_name, item_type, is_silent)
  return _depend_on_any_item({{item_name, item_type}}, is_silent, 1)
end

F.depend_on_technologies = F.depend_on_any_technology
F.depend_on_recipes = F.depend_on_any_recipe
F.depend_on_items = F.depend_on_any_item

function F.init()
  if mods['HighlyDerivative'] then
    HighlyDerivative.index()
  else
    local data_raw = data.raw
    for recipe_name,recipe in pairs(data_raw.recipe) do
      register_new_recipe(recipe, recipe_name, nil, true)
    end
    for technology_name,technology in pairs(data_raw.technology) do
      register_new_technology(technology, technology_name, nil, true)
    end
    for resource_name,resource in pairs(data_raw.resource) do
      register_new_resource(resource, resource_name, nil, true)
    end
    for mining_drill_name,mining_drill in pairs(data_raw['mining-drill']) do
      register_new_mining_drill(mining_drill, mining_drill_name, nil, true)
    end
    -- FIXME index everything!
    for mining_drill_name,mining_drill in pairs(data_raw['item']) do
      register_new_item(mining_drill, mining_drill_name, nil, true)
    end
  end
  return F
end

-- TODO mining-drill
if mods['HighlyDerivative'] then
  HighlyDerivative.register_index('technology', register_new_technology)
  HighlyDerivative.register_index('recipe', register_new_recipe)
  HighlyDerivative.register_index('resource', register_new_resource)
  HighlyDerivative.register_index('mining-drill', register_new_mining_drill)
  HighlyDerivative.register_index('item', register_new_item, true)
  HighlyDerivative.index()
end

--[[

Notes on resource dependencies.

A mining drill can extract one or more resource catagories.
mining-drill.resource_categories

A resource entity belongs to a single resource category.
resource.category

A resource entity yields some number of items and/or fluids.
resource.minable.products

A resource entity may require a fluid in order to be mined.
resource.minable.required_fluid

An item yielded by a resource is unlocked from the start if it can be mined by the vanilla character. (data.raw.character.character.mining_categories)
possibly unreliable, as we cannot tell which character may or may not be in use during the data stage.

An item/fluid yielded by a resoure is unlocked if it can be mined by a mining drill, using only fluids that have also been unlocked.

Also include the fluid yielded by any offshore pumps.
offshore_pump.fluid

]]

return F
