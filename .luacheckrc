std = "lua52c"

read_globals = {
    'log'
}

local data_settings = {
    read_globals = {
        data = {
            fields = {
                raw = {
                    read_only = false,
                    other_fields = true
                },
                extend = {}
            }
        },
        'serpent' = {
            fields = {
                'block' = {}
            }
        }
    }
}

local control_settings = {
    read_globals = {
        'script',
        'game',
        'defines',
        'serpent' = {
            fields = {
                'block' = {}
            }
        }
    },
    globals = {
        'global'
    }
}

files["control.lua"] = control_settings
files["data.lua"] = data_settings
files["data-update.lua"] = data_settings
files["data-final-fixes.lua"] = data_settings
files["prototypes/**/*.lua"] = data_settings
