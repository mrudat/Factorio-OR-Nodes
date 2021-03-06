#!perl -i.bak

use warnings;
use strict;

sub generate {
  print <<EOF;
-- begin generated functions
EOF
  my ($funcs) = [
    {
      func => 'depend_on_all_technologies',
      thing => 'technology',
      things => 'technologies',
      andor => 'and',
      all => 1,
    },
    {
      func => 'depend_on_any_technology',
      thing => 'technology',
      things => 'technologies',
      andor => 'or',
    },
    {
      func => 'depend_on_all_recipes',
      thing => 'recipe',
      things => 'recipes',
      andor => 'and',
      all => 1,
    },
    {
      func => 'depend_on_any_recipe',
      thing => 'recipe',
      things => 'recipes',
      andor => 'or',
      internal => 1,
    },
    {
      func => 'depend_on_all_items',
      thing => 'item',
      things => 'items',
      andor => 'and',
      all => 1,
    },
    {
      func => 'depend_on_any_item',
      thing => 'item',
      things => 'items',
      andor => 'or',
      internal => 1,
    }
  ];
  foreach my $data (@$funcs) {
    my $func_name = $data->{'func'};
    my $thing = $data->{'thing'};
    my $things = $data->{'things'};
    my $all = $data->{'all'};
    my $andor = $data->{'andor'};
    my $internal = $data->{'internal'};

    if ($internal) {
      print <<EOF;
local function _${func_name}(${thing}_names, is_silent, levels)
  levels = levels + 1
EOF
    } else {
      print <<EOF;
function F.${func_name}(${thing}_names, is_silent)
  local levels = 1
EOF
    }
    print <<EOF;
  if not ${thing}_names or not type(${thing}_names) == "table" then
    return report_error(is_silent, levels, "Please supply a list of ${thing} names.")
  end

EOF
    if ($all) {
      print <<EOF;
  local found_technology_names = {}
  local seen = {}
EOF
    } else {
      print <<EOF;
  local found_${thing}_names = {}
EOF
    }
    print <<EOF;
  local names = {}
  local has_${things} = false

  for ${thing}_name, difficulties in pairs(${thing}_names) do
    if type(${thing}_name) == 'number' then
      ${thing}_name = difficulties
      difficulties = 3 --[[DIFFICULTIES_BOTH]]
    end
    difficulties =  band(difficulties, 3 --[[DIFFICULTIES_MASK]])
    if difficulties == 0 then goto next_${thing} end
EOF
    if ($thing eq 'item') {
      print <<EOF;
    local ingredient_data_type = type(${thing}_name)
    local ingredient_name
    local ingredient_type
    if ingredient_data_type == 'string' then
      ingredient_name = ${thing}_name
      ingredient_type = 'item'
    elseif ingredient_data_type == 'table' then
      ingredient_name = ${thing}_name.name or ${thing}_name[1]
      ingredient_type = ${thing}_name.type or ${thing}_name[2] or 'item'
    else
      return report_error(is_silent, levels, "Supplied ingredient was neither an item name nor an ingredient prototype")
    end
EOF
    } else {
      print <<EOF;
    if not type(${thing}_name) == 'string' then
      return report_error(is_silent, levels, "One of the supplied ${thing} names was not a string")
    end
EOF
    }
    print <<EOF;
    has_${things} = true
EOF
    if ($thing eq 'item') {
      print <<EOF;
    local ${thing} = find_prototype(ingredient_name, ingredient_type, true)
EOF
    } else {
      print <<EOF;
    local ${thing} = find_prototype(${thing}_name, '${thing}', true)
EOF
    }
    if ($all) {
      print <<EOF;
    if not ${thing} then
      return report_error(is_silent, levels, 'One of the ${things} was not found.')
    end
EOF
      if ($thing eq 'item') {
        print <<EOF;
    local order = ingredient_name .. '-' .. ingredient_type
EOF
      } else {
        print <<EOF;
    local order = ${thing}_name
EOF
      }
      print <<EOF;
    local name = seen[order]
    if not name then
      name = {
        order = order,
        icon = icons_of(${thing}),
        name = locale_of(${thing})
      }
      seen[order] = name
    end
EOF
      unless ($thing eq 'technology') {
        print <<EOF;
    local technology = foobarbaz(
      {
        name_type = '${thing}',
        ${thing}_names = {
EOF
        if ($thing eq 'item') {
        print <<EOF;
          [item] = 3 --[[DIFFICULTY_BOTH]]
EOF
        } else {
        print <<EOF;
          [recipe_name] = bor(get_recipe_enabled_flags(recipe), difficulties)
EOF
        }
        print <<EOF;
        },
        name = name
      },
      levels,
      is_silent
    )
    if not technology then return nil end
EOF
      }
      print <<EOF;
    if not names[order] then
      names[order] = name
    end

EOF
      unless ($thing eq 'technology') {
        print <<EOF;
    local technology_name = technology[1]
EOF
      }
      print <<EOF;
    if not technology_name then goto next_${thing} end
    found_technology_names[technology_name] = bor(found_technology_names[technology_name] or 0, band(get_technology_enabled_flags(technology), difficulties))
EOF
    } else {
      print <<EOF;
    if not ${thing} then goto next_${thing} end
EOF
      if ($thing eq 'item') {
        print <<EOF;
    local order = ingredient_name .. '-' .. ingredient_type
EOF
      } else {
        print <<EOF;
    local order = ${thing}_name
EOF
      }
      print <<EOF;
    if not names[order] then
      names[order] = {
        order = order,
        name = locale_of(${thing}),
        icon = icons_of(${thing})
      }
    end
EOF
      if ($thing eq 'recipe') {
        print <<EOF;
    local ${thing}_mask = lshift(difficulties,2)
    found_${thing}_names[${thing}_name] = bor(found_${thing}_names[${thing}_name] or 0,
      bor(band(get_${thing}_enabled_flags(${thing}), ${thing}_mask), difficulties)
    )
EOF
      } elsif ($thing eq 'technology') {
        print <<EOF;
    found_${thing}_names[${thing}_name] = bor(found_${thing}_names[${thing}_name] or 0,
      band(get_${thing}_enabled_flags(${thing}), difficulties)
    )
EOF
      } else {
        print <<EOF;
    found_${thing}_names[item] = bor(found_${thing}_names[item] or 0, difficulties)
EOF
      }
    }
    print <<EOF;
    ::next_${thing}::
  end

  if not has_${things} then return {} end

EOF
    if(!$all) {
      print <<EOF;
  if not next(names) then
    return report_error(is_silent, levels, 'None of the ${things} were found.')
  end

EOF
    }
    if ($all) {
      print <<EOF;
  return foobarbaz_and(
EOF
    } else {
      print <<EOF;
  return foobarbaz(
EOF
    }
      print <<EOF;
    {
      name_type = '${thing}',
EOF
    if ($all) {
      print <<EOF;
      technology_names = found_technology_names,
      mode = 'and',
EOF
    } else {
      print <<EOF;
      ${thing}_names = found_${thing}_names,
EOF
    }
      print <<EOF;
      names = names
    },
    levels,
    is_silent
  )
end

EOF
    if ($internal) {
      print <<EOF;
function F.${func_name}(${thing}_names, is_silent)
  return _${func_name}(${thing}_names, is_silent, 1)
end

EOF
    }
  }
  print <<EOF;
-- end generated functions
EOF
}

my $state = 0;

my $difficulties = {
  EXPENSIVE => 2,
  NORMAL => 1,
  BOTH => 3,
  MASK => 3
};

my $availabilities = {
  EXPENSIVE => 8,
  NORMAL => 4,
  BOTH => 12,
  MASK => 12
};

while(<>) {
  s{
    ([^['])
    (DIFFICULTY_)(NORMAL|EXPENSIVE|BOTH|MASK)
    ([^]'])
  }{
    $1 . $difficulties->{$3} . " --[[$2$3]]$4"
  }gex;
  s{
    ([^['])
    (AVAILABLE_BY_DEFAULT_)(NORMAL|EXPENSIVE|BOTH|MASK)
    ([^]'])
  }{
    $1 . $availabilities->{$3} . " --[[$2$3]]$4"
  }gex;
  if (m/^-- begin generated functions/) {
    $state = 1;
    generate();
  }
  if ($state == 1) {
    if (m/^-- end generated functions/) {
      $state = 0;
    }
  } else {
    print;
  }
}
