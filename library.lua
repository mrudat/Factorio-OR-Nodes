local rusty_locale = require('__rusty-locale__/locale')
local rusty_icons = require('__rusty-locale__/icons')
local rusty_prototypes = require('__rusty-locale__/prototypes')

local locale_of = rusty_locale.of
local locale_of_recipe = rusty_locale.of_recipe
local icons_of = rusty_icons.of
local icons_of_recipe = rusty_icons.of_recipe
local find_prototype = rusty_prototypes.find

local bor = bit32.bor
local band = bit32.band
local lshift = bit32.lshift
local bnot = bit32.bnot

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

local F = {}

local MOD_NAME = "OR-Nodes"
local PREFIX = MOD_NAME .. "-"
local MOD_PATH = "__" .. MOD_NAME .. "__/"
-- local GRAPHICS_PATH = ("__%s__/graphics/"):format(MOD_NAME)
local OR_ICON = MOD_PATH .. "thumbnail.png"

local function hash(input_string)
  local h = 0
  for _,c in ipairs{string.byte(input_string,1,-1)} do
    h = band(h * 31 + c, 0xffff)
  end
  return string.format("%8.8X",h)
end

local function report_error(is_silent, levels, message)
  if is_silent then
    log(message)
    return nil
  else
    error(message, levels + 1)
  end
end

local technology_index
local dependency_index

local function build_technology_index()
  technology_index = {}
  dependency_index = {}

  local function catalog_technology(technology_name, technology_data, flags)
    local effects = technology_data.effects
    if effects then
      for _,effect in ipairs(effects) do
        if effect.type == "unlock-recipe" then
          local recipe_name = effect.recipe
          local recipe_data = technology_index[recipe_name]
          if not recipe_data then
            recipe_data = {}
            technology_index[recipe_name] = recipe_data
          end
          recipe_data[technology_name] = bor(recipe_data[technology_name] or 0, flags)
        end
      end
    end
    local prerequisites = technology_data.prerequisites
    if prerequisites then
      for _, prerequisite_name in ipairs(prerequisites) do
        local dependency_set = dependency_index[prerequisite_name]
        if not dependency_set then
          dependency_set = {}
          dependency_index[prerequisite_name] = dependency_set
        end
        dependency_set[technology_name] = bor(dependency_set[technology_name] or 0, flags)
      end
    end
  end

  for technology_name,technology in pairs(data.raw["technology"]) do
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
  return technology_index
end

local function collect_technologies_for_recipe(technology_names, recipe_name, recipe_flags)
  local recipe_data = technology_index[recipe_name]
  if not recipe_data then return end

  for technology_name, flags in pairs(recipe_data) do
    technology_names[technology_name] = bor(technology_names[technology_name] or 0, band(flags, recipe_flags))
  end
end

--[[
input dependency: a | c
tree: a -> b -> c
output dependency: c
]]
local function simplify_technologies(technology_set)
  for base_technology_name, base_difficulties in pairs(table.deepcopy(technology_set)) do
    local queue = { { base_technology_name, base_difficulties } }
    local seen = {}
    for _, head in pairs(queue) do
      local technology_name = head[1]
      local difficulties = head[2]
      local dependencies = dependency_index[technology_name]
      if not dependencies then goto next end
      for dependency, dependency_difficulties in pairs(dependencies) do
        if not seen[dependency] then
          local foo = technology_set[dependency]
          if foo then
            -- foo = foo - dependency_difficulties
            foo = band(foo, bnot(dependency_difficulties))
            if foo == 0 then
              technology_set[dependency] = nil
            else
              technology_set[dependency] = foo
            end
          end
          seen[dependency] = true
          dependency_difficulties = band(difficulties, dependency_difficulties)
          if dependency_difficulties ~= 0 then
            queue[#queue+1] = { dependency, dependency_difficulties }
          end
        end
      end
      ::next::
    end
  end
end

local recipe_index

local function build_recipe_index()
  recipe_index = {}
  local function catalog_result(recipe_name, ingredient_name, ingredient_type, recipe_flags)
    local type_data = recipe_index[ingredient_type]
    if not type_data then
      type_data = {}
      recipe_index[ingredient_type] = type_data
    end
    local ingredient_data = type_data[ingredient_name]
    if not ingredient_data then
      ingredient_data = {}
      type_data[ingredient_name] = ingredient_data
    end
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

  for recipe_name,recipe in pairs(data.raw.recipe) do
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
  return recipe_index
end

local function collect_recipes_for_item(recipes, item)
  local item_name = item.name
  local item_type = item.type
  if item_type ~= 'fluid' then
    item_type = 'item'
  end
  local type_data = recipe_index[item_type]
  if not type_data then return end
  local item_data = type_data[item_name]
  if not item_data then return end
  for recipe_name, recipe_data in pairs(item_data) do
    recipes[recipe_name] = bor(recipes[recipe_name] or 0, recipe_data)
  end
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

local function compose_names(names)
  local foo = compose_names_lookup[#names]
  local result
  if foo then
    result = {foo}
    for _, name in ipairs(names) do
      result[#result+1] = name.name
    end
    return result
  else
    result = {"OR-Nodes.list-6+"}
    for i = 1, 4 do
      result[i+1] = names[i].name
    end
    result[6] = names[#names].name
  end
  return result
end






------------------------------------------------------------------------
-- Actual technology creation.

local new_technologies = {}
local new_technologies_collisions = {}
local unnamed_technology_count = 1

local function create_or_node(node_data, levels, is_silent) --luacheck: no unused args
  local target_name = node_data.target_name
  local old_technology = new_technologies[target_name]
  if old_technology then return { old_technology } end

  local name_type = node_data.name_type

  local short_tech_name = PREFIX .. name_type .. '-' .. target_name
  if short_tech_name:len() > 200 then
    local try = ''
    repeat
      local names_hash = hash(target_name .. try)
      short_tech_name = PREFIX .. names_hash .. "-" .. target_name
      -- "…":len() == 3
      short_tech_name = short_tech_name:sub(1, 200 - 3) .. "…"
      if try == '' then
        try = 0
      else
        try = try + 1
      end
    until not new_technologies_collisions[short_tech_name]
  end

  new_technologies[target_name] = short_tech_name
  new_technologies_collisions[short_tech_name] = target_name

  local icon = node_data.icon
  local icons = node_data.icons

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
    localised_name = {"OR-Nodes-name.node-name", unnamed_technology_count}
    unnamed_technology_count = unnamed_technology_count + 1
    localised_description = compose_names(names)
    if name_type == 'items' then
      localised_description = {"OR-Nodes-description.items-craftable", localised_description}
    elseif name_type == 'recipes' then
      localised_description = {"OR-Nodes-description.recipes-craftable", localised_description}
    elseif name_type == 'technologies' then
      localised_description = {"OR-Nodes-description.technologies-craftable", localised_description}
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
      ingredients = {
        {"automation-science-pack", 1}
      },
      time = 1
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

  return { short_tech_name }
end





-------------------------------------------------------------------------
-- wrapper functions

local function create_or_node_for_technologies(node_data, levels, is_silent)
  local technology_names = node_data.technology_names
  simplify_technologies(technology_names)
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
    -- TODO correct error message.
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
  local recipe = find_prototype(recipe_name, 'recipe', is_silent)
  if not recipe then return nil end
  if get_recipe_enabled_flags(recipe) == 12 then
    return {}
  end
  return create_or_node_for_recipe(
    {
      target_name = recipe_name,
      name_type = 'recipe',
      recipe_name = recipe_name,
      icon = icons_of_recipe(recipe),
      name = locale_of_recipe(recipe)
    },
    levels + 1,
    is_silent
  )
end





--------------------------------------------------------------------------
-- public functions

function F.depend_on_technologies(technology_names, is_silent)
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

  for _,technology_name in pairs(technology_names) do
    local technology = find_prototype(technology_name, 'technology', true)
    if technology then
      technology_count = technology_count + 1
      target_names[technology_count] = technology_name
      found_technology_names[technology_name] = get_technology_enabled_flags(technology)
      icons[technology_count] = icons_of(technology)
      names[technology_count] = locale_of(technology)
    end
  end

  if technology_count == 0 then
    return report_error(is_silent, 1, 'None of the technologies were found.')
  end

  if #found_technology_names == 1 then return found_technology_names end

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

function F.depend_on_recipes(recipe_names, is_silent)
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

  for _,recipe_name in pairs(recipe_names) do
    if not type(recipe_name) == 'string' then
      return report_error(is_silent, 1, "One of the supplied recipe names was not a string")
    end
    local recipe = find_prototype(recipe_name, 'recipe', true)
    if recipe then
      recipe_count = recipe_count + 1
      target_names[recipe_count] = recipe_name
      found_recipe_names[recipe_name] = 3 + get_recipe_enabled_flags(recipe) -- DIFFICULTY_BOTH
      icons[recipe_count] = icons_of_recipe(recipe)
      names[recipe_count] = locale_of_recipe(recipe)
    end
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

function F.depend_on_items(ingredients, is_silent)
  if not ingredients or not type(ingredients) == "table" then
    return report_error(is_silent, 1, "Please supply a list of ingredients.")
  end

  if #ingredients == 0 then return {} end

  for i,ingredient in ipairs(ingredients) do
    local ingredient_type = type(ingredient)
    if ingredient_type == 'string' then
      ingredients[i] = {
        name = ingredient,
        type = 'item'
      }
    elseif ingredient_type == 'table' then
      if not ingredient.name then
        ingredient.name = ingredient[1]
        ingredient[1] = nil
        ingredient.type = ingredient[2] or 'item'
        ingredient[2] = nil
      end
    else
      return report_error(is_silent, 1, "Supplied ingredient was neither an item name nor an ingredient prototype")
    end
  end

  if #ingredients == 1 then
    local ingredient = ingredients[1]
    return _depend_on_item(ingredient.name, ingredient.type, is_silent, 2)
  end

  table.sort(ingredients, function (a, b) return a.name < b.name end)

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
    return report_error(is_silent, 1, 'None of the items were found.')
  end

  return create_or_node_for_items(
    {
      target_name = table.concat(target_names, '-or-'),
      name_type = 'items',
      items = items,
      names = names,
      icons = icons
    },
    1,
    is_silent
  )
end

function F.depend_on_item(item_name, item_type, is_silent)
  return _depend_on_item(item_name, item_type, is_silent, 1)
end

return {
  init = function()
    build_technology_index()
    build_recipe_index()
    return F
  end
}
