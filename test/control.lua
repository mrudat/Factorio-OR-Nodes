script.on_event(defines.events.on_research_finished, function(event)
  local technology = event.research
  local technology_name = technology.name
  local force = technology.force
  force.print({"", "Technology unlocked: ", technology_name})
end
)
