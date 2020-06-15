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
local locale_of_recipe = rusty_locale.of_recipe
local icons_of = rusty_icons.of
local icons_of_recipe = rusty_icons.of_recipe
local find_prototype = rusty_prototypes.find

local bor = bit32.bor
local band = bit32.band
local lshift = bit32.lshift
local bnot = bit32.bnot





--------------------------------------------------------------------------------
-- constants

--[[

-- recipe flags
#define AVAILABILE_BY_DEFAULT_MASK    12
#define AVAILABLE_BY_DEFAULT_EXPENSIVE 8
#define AVAILABLE_BY_DEFAULT_NORMAL    4
#define AVAILABLE_BY_DEFAULT_BOTH     12

-- difficulty 'constants'
#define DIFFICULTY_EXPENSIVE 2
#define DIFFICULTY_NORMAL    1
#define DIFFICULTY_BOTH      3
#define DIFFICULTY_MASK      3

]]

local MOD_NAME = "OR-Nodes"
local PREFIX_OR = MOD_NAME .. "-or-"
local PREFIX_AND = MOD_NAME .. "-and-"
local MOD_PATH = "__" .. MOD_NAME .. "__/"
-- local GRAPHICS_PATH = ("__%s__/graphics/"):format(MOD_NAME)
local OR_ICON = MOD_PATH .. "thumbnail.png"
-- TODO create icon.
--local AND_ICON = MOD_PATH .. "graphics/and.png"





--------------------------------------------------------------------------------
-- package variables

F.recipe_name_to_technology_names = {}
F.technology_name_to_dependent_technology_names = {}
F.recipe_index = {}
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

local function catalog_technology(technology_name, technology_data, flags)
  local recipe_name_to_technology_names = F.recipe_name_to_technology_names
  local technology_name_to_dependent_technology_names = F.technology_name_to_dependent_technology_names
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
    for _, prerequisite_name in ipairs(prerequisites) do
      local dependent_technology_names = autovivify(technology_name_to_dependent_technology_names, prerequisite_name)
      dependent_technology_names[technology_name] = bor(dependent_technology_names[technology_name] or 0, flags)
    end
  end
end

local function register_new_technology(technology, technology_name, _, is_refresh)
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
      catalog_technology(technology_name, normal, 3) -- DIFFICULTY_BOTH
    elseif not normal then
      catalog_technology(technology_name, expensive, 3) -- DIFFICULTY_BOTH
    else
      catalog_technology(technology_name, normal, 1) -- DIFFICULTY_NORMAL
      catalog_technology(technology_name, expensive, 2) -- DIFFICULTY_EXPENSIVE
    end
  else
    catalog_technology(technology_name, technology, 3) -- DIFFICULTY_BOTH
  end
end

local function build_technology_index()
  for technology_name,technology in pairs(data.raw["technology"]) do
    register_new_technology(technology, technology_name)
  end
end

local function collect_technologies_for_recipe(technology_names, recipe_name, recipe_flags)
  local recipe_data = F.recipe_name_to_technology_names[recipe_name]
  if not recipe_data then return end

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
      catalog_recipe(recipe_name, normal, false, 1) -- DIFFICULTY_NORMAL
      catalog_recipe(recipe_name, normal, true, 2) -- DIFFICULTY_EXPENSIVE
    elseif normal == false then
      catalog_recipe(recipe_name, expensive, false, 2) -- DIFFICULTY_EXPENSIVE
      catalog_recipe(recipe_name, expensive, true, 1) -- DIFFICULTY_NORMAL
    elseif expensive == nil then
      catalog_recipe(recipe_name, normal, false, 3) -- DIFFICULTY_BOTH
    elseif normal == nil then
      catalog_recipe(recipe_name, expensive, false, 3) -- DIFFICULTY_BOTH
    else
      catalog_recipe(recipe_name, normal, false, 1) -- DIFFICULTY_NORMAL
      catalog_recipe(recipe_name, expensive, false, 2) -- DIFFICULTY_EXPENSIVE
    end
  else
    catalog_recipe(recipe_name, recipe, false, 3) -- DIFFICULTY_BOTH
  end
end

local function build_recipe_index()
  for recipe_name,recipe in pairs(data.raw.recipe) do
    register_new_recipe(recipe, recipe_name)
  end
end

local function collect_recipes_for_item(recipes, item)
  local item_name = item.name
  local item_type = item.type
  -- TODO support for items required in only certain difficulties
  --local item_flags = item.flags or 3
  --local item_mask = bor(item_flags, lshift(item_flags,2))
  if item_type ~= 'fluid' then
    item_type = 'item'
  end
  local type_data = F.recipe_index[item_type]
  if not type_data then return end
  local item_data = type_data[item_name]
  if not item_data then return end
  for recipe_name, recipe_data in pairs(item_data) do
    recipes[recipe_name] = bor(recipes[recipe_name] or 0, recipe_data)
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
        return 1 -- DIFFICULTY_NORMAL
      end
      return 0
    elseif normal == false then
      if expensive.enabled ~= false then
        return 2 -- DIFFICULTY_EXPENSIVE
      end
      return 0
    elseif expensive == nil then
      if normal.enabled ~= false then
        return 3 -- DIFFICULTY_BOTH
      end
      return 0
    elseif normal == nil then
      if expensive.enabled ~= false then
        return 3 -- DIFFICULTY_BOTH
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
      return 3 -- DIFFICULTY_BOTH
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
        return 4 -- AVAILABLE_BY_DEFAULT_NORMAL
      end
      return 0
    elseif normal == false then
      if expensive.enabled ~= false then
        return 8 -- AVAILABLE_BY_DEFAULT_EXPENSIVE
      end
      return 0
    elseif expensive == nil then
      if normal.enabled ~= false then
        return 12 -- AVAILABLE_BY_DEFAULT_BOTH
      end
      return 0
    elseif normal == nil then
      if expensive.enabled ~= false then
        return 12 -- AVAILABLE_BY_DEFAULT_BOTH
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
      return 12 -- AVAILABLE_BY_DEFAULT_BOTH
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

  local icon = node_data.icon
  local icons = node_data.icons

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

  local name = node_data.name
  local names = node_data.names

  local localised_name
  local localised_description

  if names then
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
  elseif name then
    localised_name = name.name
    if name_type == 'item' then
      localised_description = {"OR-Nodes-description.item-craftable", localised_name}
    elseif name_type == 'recipe' then
      localised_description = {"OR-Nodes-description.recipe-craftable", localised_name}
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
    if band(difficulties,3) == 3 then
      prerequisites[#prerequisites+1] = technology_name
    elseif band(difficulties,1) == 1 then
      normal_prerequisites[#normal_prerequisites+1] = technology_name
    elseif band(difficulties,2) == 2 then
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

  data:extend{ technology }

  if HighlyDerivative then HighlyDerivative.index(technology) end

  return { short_tech_name }
end





-------------------------------------------------------------------------
-- wrapper functions

local function create_or_node_for_technologies(node_data, levels, is_silent)
  local mode = node_data.mode
  local and_mode = false
  if mode and mode == 'and' then and_mode = true end
  local technology_names = node_data.technology_names
  if and_mode then
    simplify_technologies2(technology_names)
  else
    simplify_technologies(technology_names)
  end
  local technology_name, technology_flags = next(technology_names)
  if not technology_name then
    -- shouldn't happen?
    return report_error(is_silent, levels + 1, "Shouldn't happen, after filtering out redundant requirements, no technologies remain to depend upon.")
  end
  if next(technology_names, technology_name) then
    node_data.technology_names = technology_names
    return create_or_node(node_data, levels + 1, is_silent)
  end
  if band(technology_flags, 3) ~= 3 then -- DIFFICULTIES_BOTH
    return report_error(is_silent, levels + 1, 'The technology found does not exist on all difficulty levels')
  end
  return { technology_name }
end

local function create_or_node_for_recipe(node_data, levels, is_silent)
  local technology_names = {}
  local recipe_name = node_data.recipe_name
  collect_technologies_for_recipe(technology_names, recipe_name, 3)
  local technology_name, technology_flags = next(technology_names)
  if not technology_name then
    return report_error(is_silent, levels + 1, 'No technologies were found to unlock the recipe, and the recipe is not unlocked by default')
  end
  if next(technology_names, technology_name) then
    node_data.technology_names = technology_names
    return create_or_node_for_technologies(node_data, levels + 1, is_silent)
  end
  if band(technology_flags, 3) ~= 3 then -- DIFFICULTIES_BOTH
    return report_error(is_silent, levels + 1, 'Only one technology was found to unlock the recipe, but it does not exist on all difficulty levels')
  end
  return { technology_name }
end

local function create_or_node_for_recipes(node_data, levels, is_silent)
  local technology_names = {}
  local recipe_names = node_data.recipe_names
  local combined_recipe_flags = 0
  for recipe_name, recipe_flags in pairs(recipe_names) do
    collect_technologies_for_recipe(technology_names, recipe_name, recipe_flags)
    combined_recipe_flags = bor(combined_recipe_flags, recipe_flags)
    if band(combined_recipe_flags, 12) == 12 then -- AVAILABLE_BY_DEFAULT_BOTH
      return {}
    end
  end
  local technology_name, technology_flags = next(technology_names)
  if not technology_name then
    return report_error(is_silent, levels + 1, 'No technologies were found that unlock any of the recipies')
  end
  if next(technology_names, technology_name) then
    node_data.technology_names = technology_names
    return create_or_node_for_technologies(node_data, levels + 1, is_silent)
  end
  if band(technology_flags, 3) ~= 3 then -- DIFFICULTIES_BOTH
    return report_error(is_silent, levels + 1, 'Only one technology was found that unlocks any of the recipes, but it does not exist on all difficulty levels')
  end
  return { technology_name }
end

local function create_or_node_for_item(node_data, levels, is_silent)
  -- TODO support for items required in only certain difficulties
  local recipe_names = {}
  collect_recipes_for_item(recipe_names, node_data.item)
  local combined_recipe_flags = 0
  for _, recipe_flags in pairs(recipe_names) do
    combined_recipe_flags = bor(combined_recipe_flags, recipe_flags)
    if band(combined_recipe_flags, 12) == 12 then -- AVAILABLE_BY_DEFAULT_BOTH
      return {}
    end
  end
  local recipe_name, recipe_flags = next(recipe_names)
  if not recipe_name then
    return report_error(is_silent, levels + 1, 'The item is not craftable by any recipe')
  end
  if next(recipe_names, recipe_name) then
    node_data.recipe_names = recipe_names
    return create_or_node_for_recipes(node_data, levels + 1, is_silent)
  end
  if band(recipe_flags, 3) ~= 3 then -- DIFFICULTIES_BOTH
    return report_error(is_silent, levels + 1, 'The item is not able to be crafted on all difficulties')
  end
  node_data.recipe_name = recipe_name
  return create_or_node_for_recipe(node_data, levels + 1, is_silent)
end

local function create_or_node_for_items(node_data, levels, is_silent)
  -- TODO support for items required in only certain difficulties
  local recipe_names = {}
  local items = node_data.items
  for _,item in ipairs(items) do
    collect_recipes_for_item(recipe_names, item)
  end
  local recipe_name, difficulties = next(recipe_names)
  if not recipe_name then
    return report_error(is_silent, levels + 1, 'None of the items were created by any recipe')
  end
  if next(recipe_names, recipe_name) then
    node_data.recipe_names = recipe_names
    return create_or_node_for_recipes(node_data, levels + 1, is_silent)
  end
  if band(difficulties,12) == 12 then -- DIFFICULTIES_BOTH
    return {}
  end
  if band(difficulties,3) ~= 3 then -- DIFFICULTIES_BOTH
    return report_error(is_silent, levels + 1, 'Only one of the items is craftable by any recipe, but that recipe only exists in one difficulty')
  end
  node_data.recipe_name = recipe_name
  return create_or_node_for_recipe(node_data, levels + 1, is_silent)
end





--------------------------------------------------------------------------
-- functions with parameter checking

local function _depend_on_item(item_name, item_type, is_silent, levels)
  if not item_name or not type(item_name) == "string" then
    return report_error(is_silent, levels, "Please supply an ingredient name.")
  end
  local item = find_prototype(item_name, item_type or 'item', true)
  if not item then
    return report_error(is_silent, levels, 'Item not found')
  end
  item_type = item.type
  return create_or_node_for_item(
    {
      target_name = item_type .. '-' .. item_name,
      name_type = 'item',
      item = {
        name = item_name,
        type = item_type
      },
      name = locale_of(item),
      icon = icons_of(item)
    },
    levels + 1,
    is_silent
  )
end

local function _depend_on_recipe(recipe_name, is_silent, levels)
  local recipe
  local recipe_type = type(recipe_name)
  if recipe_type == 'table' then
    recipe = recipe_name
    recipe_name = recipe.name
    if not recipe_name then
      return report_error(is_silent, 1, "Supplied recipe prototype does not have a name")
    end
  elseif recipe_type == 'string' then
    recipe = find_prototype(recipe_name, 'recipe', is_silent)
  else
    return report_error(is_silent, 1, "Supplied recipe was neither a recipe name nor a recipe protoype")
  end
  if not recipe then
    return report_error(is_silent, 1, "Could not find a recipe with the supplied name")
  end
  if get_recipe_enabled_flags(recipe) == 12 then
    return {}
  end
  return create_or_node_for_recipe(
    {
      target_name = recipe_name,
      name_type = 'recipe',
      recipe_name = recipe_name,
      icon = icons_of_recipe(recipe),
      name = locale_of_recipe(recipe),
    },
    levels + 1,
    is_silent
  )
end

local function _depend_on_items(ingredients, is_silent, level)
  if not ingredients or not type(ingredients) == "table" then
    return report_error(is_silent, level + 1, "Please supply a list of ingredients.")
  end

  if #ingredients == 0 then return {} end

  do
    local items = {}
    local fluids = {}

    for i = 1,#ingredients do
      local ingredient = ingredients[i]
      local ingredient_type = type(ingredient)
      if ingredient_type == 'string' then
        items[ingredient] = 'item'
      elseif ingredient_type == 'table' then
        local name = ingredients.name or ingredient[1]
        local itype = ingredient.type or ingredient[2] or 'item'
        if itype == 'fluid' then
          fluids[name] = true
        else
          items[name] = itype
        end
      else
        return report_error(is_silent, level + 1, "Supplied ingredient was neither an item name nor an ingredient prototype")
      end
    end
    ingredients = {}

    for item_name, item_type in pairs(items) do
      ingredients[#ingredients+1] = {
        name = item_name,
        type = item_type
      }
    end

    for fluid_name in pairs(fluids) do
      ingredients[#ingredients+1] = {
        name = fluid_name,
        type = 'fluid'
      }
    end
  end

  if #ingredients == 1 then
    local ingredient = ingredients[1]
    return _depend_on_item(ingredient.name, ingredient.type, is_silent, level + 1)
  end

  table.sort(ingredients, function (a, b)
    if a.name == b.name then return a.type < b.type end
    return a.name < b.name
  end)

  local items = {}
  local names = {}
  local icons = {}
  local item_index = 0
  local target_names = {}

  for _,ingredient in ipairs(ingredients) do
    local item = find_prototype(ingredient.name, ingredient.type, true)
    if item then
      item_index = item_index + 1
      items[item_index] = item
      names[item_index] = locale_of(item)
      icons[item_index] = icons_of(item)
      target_names[#target_names + 1] = item.type .. '-' .. item.name
    end
  end

  if #items == 0 then
    return report_error(is_silent, level + 1, 'None of the items were found.')
  end

  return create_or_node_for_items(
    {
      target_name = table.concat(target_names, '-or-'),
      name_type = 'items',
      items = items,
      names = names,
      icons = icons
    },
    level + 1,
    is_silent
  )
end





--------------------------------------------------------------------------
-- public functions

function F.depend_on_all_technologies(technology_names, is_silent)
  if not technology_names or not type(technology_names) == "table" then
    return report_error(is_silent, 1, "Please supply a list of technology names.")
  end

  if #technology_names == 0 then return {} end
  if #technology_names == 1 then return { technology_names[1] } end

  local found_technology_names = {}
  local target_names = {}
  local icons = {}
  local names = {}
  local technology_count = 0

  table.sort(technology_names)

  local seen = {}

  for i = 1,#technology_names do
    local technology_name = technology_names[i]
    if not type(technology_name) == 'string' then
      return report_error(is_silent, 1, "One of the supplied technology names was not a string")
    end
    if seen[technology_name] then goto next_technology end
    seen[technology_name] = true
    local technology = find_prototype(technology_name, 'technology', true)
    if not technology then
      return report_error(is_silent, 1, 'One of the technologies was not found.')
    end
    technology_count = technology_count + 1
    target_names[technology_count] = technology_name
    found_technology_names[technology_name] = get_technology_enabled_flags(technology)
    icons[technology_count] = icons_of(technology)
    names[technology_count] = locale_of(technology)
    ::next_technology::
  end

  return create_or_node_for_technologies(
    {
      target_name = table.concat(target_names, '-and-'),
      technology_names = found_technology_names,
      name_type = 'technologies',
      icons = icons,
      names = names,
      mode = 'and'
    },
    1,
    is_silent
  )
end

function F.depend_on_any_technology(technology_names, is_silent)
  if not technology_names or not type(technology_names) == "table" then
    return report_error(is_silent, 1, "Please supply a list of technology names.")
  end

  if #technology_names == 0 then return {} end
  if #technology_names == 1 then return { technology_names[1] } end

  local found_technology_names = {}
  local target_names = {}
  local icons = {}
  local names = {}
  local technology_count = 0

  table.sort(technology_names)

  local seen = {}

  for i = 1, #technology_names do
    local technology_name = technology_names[i]
    if not type(technology_name) == 'string' then
      return report_error(is_silent, 1, "One of the supplied technology names was not a string")
    end
    if seen[technology_name] then goto next_technology end
    seen[technology_name] = true
    local technology = find_prototype(technology_name, 'technology', true)
    if not technology then goto next_technology end
    technology_count = technology_count + 1
    target_names[technology_count] = technology_name
    found_technology_names[technology_name] = get_technology_enabled_flags(technology)
    icons[technology_count] = icons_of(technology)
    names[technology_count] = locale_of(technology)
    ::next_technology::
  end

  if technology_count == 0 then
    return report_error(is_silent, 1, 'None of the technologies were found.')
  end

  if technology_count == 1 then
    local technology_name = next(found_technology_names)
    return { technology_name }
  end

  return create_or_node_for_technologies(
    {
      target_name = table.concat(target_names, '-or-'),
      technology_names = found_technology_names,
      name_type = 'technologies',
      icons = icons,
      names = names
    },
    1,
    is_silent
  )
end

function F.depend_on_all_recipes(recipe_names, is_silent)
  if not recipe_names or not type(recipe_names) == "table" then
    return report_error(is_silent, 1, "Please supply a list of recipe names.")
  end

  if #recipe_names == 0 then return {} end
  if #recipe_names == 1 then
    return _depend_on_recipe(recipe_names[1], is_silent, 2)
  end

  table.sort(recipe_names)

  local found_technology_names = {}
  local target_names = {}
  local icons = {}
  local names = {}
  local recipe_count = 0

  local seen_recipe = {}
  local seen_technology = {}

  for i = 1, #recipe_names do
    local recipe_name = recipe_names[i]
    if not type(recipe_name) == 'string' then
      return report_error(is_silent, 1, "One of the supplied recipe names was not a string")
    end
    if seen_recipe[recipe_name] then goto next_recipe end
    seen_recipe[recipe_name] = true
    local recipe = find_prototype(recipe_name, 'recipe', true)
    if not recipe then
      return report_error(is_silent, 1, 'One of the recipes was not found.')
    end
    local technology = _depend_on_recipe(recipe_name, is_silent, 1)
    if not technology then return nil end
    local technology_name = technology[1]
    if not technology_name then goto next_recipe end
    if seen_technology[technology_name] then goto next_recipe end
    seen_technology[technology_name] = true
    technology = find_prototype(technology_name, 'technology', true)
    found_technology_names[technology_name] = get_technology_enabled_flags(technology)
    recipe_count = recipe_count + 1
    target_names[recipe_count] = recipe_name
    icons[recipe_count] = icons_of_recipe(recipe)
    names[recipe_count] = locale_of_recipe(recipe)
    ::next_recipe::
  end

  local technology_name, technology_flags = next(found_technology_names)
  if not technology_name then return {} end
  if next(found_technology_names, technology_name) then
    return create_or_node_for_technologies(
      {
        target_name = table.concat(target_names, '-and-'),
        name_type = 'recipes',
        technology_names = found_technology_names,
        icons = icons,
        names = names,
        mode = 'and'
      },
      2,
      is_silent
    )
    end
  -- TODO what if the item required and technology exist only in one difficulty?
  if band(technology_flags, 3) ~= 3 then -- DIFFICULTIES_BOTH
    return report_error(is_silent, 1, 'The technology found does not exist on all difficulty levels')
  end
  return { technology_name }
end

function F.depend_on_any_recipe(recipe_names, is_silent)
  if not recipe_names or not type(recipe_names) == "table" then
    return report_error(is_silent, 1, "Please supply a list of recipe names.")
  end

  if #recipe_names == 0 then return {} end
  if #recipe_names == 1 then
    return _depend_on_recipe(recipe_names[1], is_silent, 2)
  end

  table.sort(recipe_names)

  local target_names = {}
  local found_recipe_names = {}
  local icons = {}
  local names = {}
  local recipe_count = 0

  local seen = {}

  for _,recipe_name in pairs(recipe_names) do
    if not type(recipe_name) == 'string' then
      return report_error(is_silent, 1, "One of the supplied recipe names was not a string")
    end
    if seen[recipe_name] then goto next_recipe end
    seen[recipe_name] = true
    local recipe = find_prototype(recipe_name, 'recipe', true)
    if not recipe then goto next_recipe end
    recipe_count = recipe_count + 1
    target_names[recipe_count] = recipe_name
    found_recipe_names[recipe_name] = 3 + get_recipe_enabled_flags(recipe) -- DIFFICULTY_BOTH
    icons[recipe_count] = icons_of_recipe(recipe)
    names[recipe_count] = locale_of_recipe(recipe)
    ::next_recipe::
  end

  if recipe_count == 0 then
    return report_error(is_silent, 1, 'None of the recipes were found.')
  end

  return create_or_node_for_recipes(
    {
      target_name = table.concat(target_names, '-or-'),
      name_type = 'recipes',
      recipe_names = found_recipe_names,
      icons = icons,
      names = names
    },
    2,
    is_silent
  )
end

function F.depend_on_recipe(recipe_name, is_silent)
  return _depend_on_recipe(recipe_name, is_silent, 1)
end

function F.depend_on_all_items(ingredients, is_silent)
  do
    local items = {}
    local fluids = {}

    for i = 1,#ingredients do
      local ingredient = ingredients[i]
      local ingredient_type = type(ingredient)
      if ingredient_type == 'string' then
        items[ingredient] = 'item'
      elseif ingredient_type == 'table' then
        local name = ingredients.name or ingredient[1]
        local itype = ingredient.type or ingredient[2] or 'item'
        if itype == 'fluid' then
          fluids[name] = true
        else
          items[name] = itype
        end
      else
        return report_error(is_silent, 1, "Supplied ingredient was neither an item name nor an ingredient prototype")
      end
    end
    ingredients = {}

    for item_name, item_type in pairs(items) do
      ingredients[#ingredients+1] = {
        name = item_name,
        type = item_type
      }
    end

    for fluid_name in pairs(fluids) do
      ingredients[#ingredients+1] = {
        name = fluid_name,
        type = 'fluid'
      }
    end
  end

  if #ingredients == 0 then return {} end

  if #ingredients == 1 then
    local ingredient = ingredients[1]
    return _depend_on_item(ingredient.name, ingredient.type, is_silent, 1)
  end

  table.sort(ingredients, function (a, b)
    if a.name == b.name then return a.type < b.type end
    return a.name < b.name
  end)

  local target_names = {}
  local names = {}
  local icons = {}
  local found_technology_names = {}
  local item_index = 0

  for i = 1,#ingredients do
    local ingredient = ingredients[i]
    local ingredient_name = ingredient.name
    local ingredient_type = ingredient.type
    local item = find_prototype(ingredient_name, ingredient_type, true)
    if not item then
      return report_error(is_silent, 1, 'One of the items was not found.')
    end
    ingredient_type = item.type

    item_index = item_index + 1
    names[item_index] = locale_of(item)
    icons[item_index] = icons_of(item)
    target_names[#target_names + 1] = ingredient_type .. '-' .. ingredient_name

    local technology = _depend_on_item(ingredient_name, ingredient_type, is_silent, 1)
    if not technology then return nil end
    local technology_name = technology[1]
    if not technology_name then goto next_ingredient end
    if found_technology_names[technology_name] then goto next_ingredient end
    technology = find_prototype(technology_name, 'technology', true)
    found_technology_names[technology_name] = get_technology_enabled_flags(technology)
    ::next_ingredient::
  end

  local technology_name, technology_flags = next(found_technology_names)
  if not technology_name then return {} end
  if next(found_technology_names, technology_name) then
    return create_or_node_for_technologies(
      {
        target_name = table.concat(target_names, '-and-'),
        name_type = 'items',
        technology_names = found_technology_names,
        names = names,
        icons = icons,
        mode = 'and'
      },
      1,
      is_silent
    )
  end
  -- TODO what if the item required and technology exist only in one difficulty?
  if band(technology_flags, 3) ~= 3 then -- DIFFICULTIES_BOTH
    return report_error(is_silent, 1, 'The technology found does not exist on all difficulty levels')
  end
  return { technology_name }
end

function F.depend_on_all_recipe_ingredients(recipe, is_silent)
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
  end
  if not recipe then
    return report_error(is_silent, 1, "Could not find a recipe with the supplied name")
  end

  -- ingredients[fluid/item][name] = difficulties
  local temp_ingredients = {}

  local function collect_ingredients(recipe_data, flags)
    local recipe_ingredients = recipe_data.ingredients
    for i = 1,#recipe_ingredients do
      local ingredient = recipe_ingredients[i]
      local ingredient_type = ingredient.type or 'item'
      local foo = autovivify(temp_ingredients, ingredient_type)
      local ingredient_name
      if ingredient_type == 'fluid' then
        ingredient_name = ingredient.name
      else
        ingredient_name = ingredient.name or ingredient[1]
      end
      foo[ingredient_name] = bor(foo[ingredient_name] or 0, flags)
    end
  end

  local normal = recipe.normal
  local expensive = recipe.expensive

  if expensive or normal then
    if not expensive then
      collect_ingredients(normal, 3) -- DIFFICULTY_BOTH
    elseif not normal then
      collect_ingredients(expensive, 3) -- DIFFICULTY_BOTH
    else
      collect_ingredients(normal, 1) -- DIFFICULTY_NORMAL
      collect_ingredients(expensive, 2) -- DIFFICULTY_EXPENSIVE
    end
  else
    collect_ingredients(recipe, 3) -- DIFFICULTY_BOTH
  end

  local found_technology_names = {}

  for ingredient_type, foo in pairs(temp_ingredients) do
    for ingredient_name, flags in pairs(foo) do
      local technology = _depend_on_item(ingredient_name, ingredient_type, is_silent, 1)
      if not technology then return nil end
      local technology_name = technology[1]
      if not technology_name then goto next_ingredient end
      technology = find_prototype(technology_name, 'technology', true)
      -- TODO what if the item required and technology exist only in one difficulty?
      found_technology_names[technology_name] = bor(
        found_technology_names[technology_name] or 0,
        band(get_technology_enabled_flags(technology), flags)
      )
      ::next_ingredient::
    end
  end

  local technology_name, technology_flags = next(found_technology_names)
  if not technology_name then return {} end
  if next(found_technology_names, technology_name) then
    return create_or_node_for_technologies(
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
  if band(technology_flags, 3) ~= 3 then -- DIFFICULTIES_BOTH
    return report_error(is_silent, 1, 'The technology found does not exist on all difficulty levels')
  end
  return { technology_name }
end

function F.depend_on_any_item(ingredients, is_silent)
  return _depend_on_items(ingredients, is_silent, 1)
end

function F.depend_on_item(item_name, item_type, is_silent)
  return _depend_on_item(item_name, item_type, is_silent, 1)
end

F.depend_on_technologies = F.depend_on_any_technology
F.depend_on_recipes = F.depend_on_any_recipe
F.depend_on_items = F.depend_on_any_item

function F.init()
  if mods['HighlyDerivative'] then
    HighlyDerivative.index()
  else
    build_technology_index()
    build_recipe_index()
  end
  return F
end

if mods['HighlyDerivative'] then
  HighlyDerivative.register_index('technology', register_new_technology)
  HighlyDerivative.register_index('recipe', register_new_recipe)
  HighlyDerivative.index()
end

return F
