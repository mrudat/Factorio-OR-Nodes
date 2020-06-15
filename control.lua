local PREFIX_OR = "OR-Nodes-or-"
local PREFIX_AND = "OR-Nodes-and-"

local is_or_node
do
  local PREFIX_LENGTH = PREFIX_OR:len()
  function is_or_node(name)
    return name:sub(1, PREFIX_LENGTH) == PREFIX_OR
  end
end

local is_and_node
do
  local PREFIX_LENGTH = PREFIX_AND:len()
  function is_and_node(name)
    return name:sub(1, PREFIX_LENGTH) == PREFIX_AND
  end
end

local function autovivify(table, key)
  local foo = table[key]
  if not foo then
    foo = {}
    table[key] = foo
  end
  return foo
end

local get_or_nodes_to_unlock
local get_and_nodes_to_unlock
do
  local or_node_index = {}
  local and_node_index = {}

  local function build_technology_index()
    for technology_name,technology in pairs(game.technology_prototypes) do
      if is_or_node(technology_name) then
        for prerequisite_name in pairs(technology.prerequisites) do
          local technologies_to_unlock = autovivify(or_node_index,prerequisite_name)
          technologies_to_unlock[#technologies_to_unlock + 1] = technology_name
        end
      elseif is_and_node(technology_name) then
        for prerequisite_name in pairs(technology.prerequisites) do
          local technologies_to_unlock = autovivify(and_node_index,prerequisite_name)
          technologies_to_unlock[#technologies_to_unlock + 1] = technology_name
        end
      end
    end
  end

  local function _get_or_nodes_to_unlock(technology)
    return or_node_index[technology]
  end

  local function _get_and_nodes_to_unlock(technology)
    return and_node_index[technology]
  end

  function get_or_nodes_to_unlock(technology)
    build_technology_index()
    get_or_nodes_to_unlock = _get_or_nodes_to_unlock
    get_and_nodes_to_unlock = _get_and_nodes_to_unlock
    return get_or_nodes_to_unlock(technology)
  end

  function get_and_nodes_to_unlock(technology)
    build_technology_index()
    get_or_nodes_to_unlock = _get_or_nodes_to_unlock
    get_and_nodes_to_unlock = _get_and_nodes_to_unlock
    return get_and_nodes_to_unlock(technology)
  end
end

local function on_research_finished(event)
  local technology = event.research
  local technology_name = technology.name
  local technologies_to_unlock = get_or_nodes_to_unlock(technology_name)
  if technologies_to_unlock then
    local force = technology.force
    local technologies = force.technologies
    for _, technology_to_unlock_name in ipairs(technologies_to_unlock) do
      technologies[technology_to_unlock_name].researched = true
    end
  end
  technologies_to_unlock = get_and_nodes_to_unlock(technology_name)
  if technologies_to_unlock then -- TODO there's sure to be a better way.
    local force = technology.force
    local technologies = force.technologies
    for _, technology_to_unlock_name in ipairs(technologies_to_unlock) do
      local tech = technologies[technology_to_unlock_name]
      for _, tech2 in pairs(tech.prerequisites) do
        if not tech2.researched then goto next_tech end
      end
      tech.researched = true
      ::next_tech::
    end
  end
end

local function unlock_technologies()
  for _,force in pairs(game.forces) do
    local technologies = force.technologies
    for technology_name,technology in pairs(technologies) do
      if not technology.researched then goto next_technology end
      local technologies_to_unlock = get_or_nodes_to_unlock(technology_name)
      if technologies_to_unlock then
        for _, technology_to_unlock_name in ipairs(technologies_to_unlock) do
          technologies[technology_to_unlock_name].researched = true
        end
      end
      technologies_to_unlock = get_and_nodes_to_unlock(technology_name)
      if technologies_to_unlock then -- TODO there's sure to be a better way.
        for _, technology_to_unlock_name in ipairs(technologies_to_unlock) do
          local tech = technologies[technology_to_unlock_name]
          for _, tech2 in pairs(tech.prerequisites) do
            if not tech2.researched then goto next_tech end
          end
          tech.researched = true
          ::next_tech::
        end
      end
          ::next_technology::
    end
  end
end

script.on_event(defines.events.on_research_finished, on_research_finished)
script.on_configuration_changed(unlock_technologies)
script.on_init(unlock_technologies)
