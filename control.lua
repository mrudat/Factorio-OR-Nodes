local util = require("util")

local PREFIX = "OR-Nodes-"

local is_ours
do
  local PREFIX_LENGTH = PREFIX:len()
  function is_ours(name)
    return name:sub(1, PREFIX_LENGTH) == PREFIX
  end
end

local get_technolgies_to_unlock
do
  local technology_index = {}

  local function build_technology_index()
    local technology_index = technology_index
    local is_ours = is_ours
    for technology_name,technology in pairs(game.technology_prototypes) do
      if not is_ours(technology_name) then goto next_technology end
      for prerequisite_name in pairs(technology.prerequisites) do
        local technologies_to_unlock = technology_index[prerequisite_name]
        if not technologies_to_unlock then
          technologies_to_unlock = {}
          technology_index[prerequisite_name] = technologies_to_unlock
        end
        technologies_to_unlock[#technologies_to_unlock + 1] = technology_name
      end
      ::next_technology::
    end
  end

  local function _get_technolgies_to_unlock(technology)
    return technology_index[technology]
  end

  function get_technolgies_to_unlock(technology)
    build_technology_index()
    get_technolgies_to_unlock = _get_technolgies_to_unlock
    return get_technolgies_to_unlock(technology)
  end
end

local function on_research_finished(event)
  local technology = event.research
  local technologies_to_unlock = get_technolgies_to_unlock(technology.name)
  if not technologies_to_unlock then return end
  local force = technology.force
  local technologies = force.technologies
  for _, technology_to_unlock_name in ipairs(technologies_to_unlock) do
    technologies[technology_to_unlock_name].researched = true
  end
end


local function unlock_technologies()
  for _,force in pairs(game.forces) do
    local technologies = force.technologies
    for technology_name,technology in pairs(technologies) do
      if not technology.researched then goto next_technology end
      local technologies_to_unlock = get_technolgies_to_unlock(technology_name)
      if not technologies_to_unlock then goto next_technology end
      for _, technology_to_unlock_name in ipairs(technologies_to_unlock) do
        technologies[technology_to_unlock_name].researched = true
      end
      ::next_technology::
    end
  end
end

script.on_event(defines.events.on_research_finished, on_research_finished)
script.on_configuration_changed(unlock_technologies)
script.on_init(unlock_technologies)
