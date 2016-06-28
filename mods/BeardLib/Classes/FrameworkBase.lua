FrameworkBase = FrameworkBase or class()
FrameworkBase._directory = ""

function FrameworkBase:init()
    self._loaded_configs = {}
    self._config_calls = table.merge(self._config_calls or {}, {
        localization = {func = callback(self, self, "LoadLocalizationConfig")}
    })

    self:Load()
end

function FrameworkBase:Load()
    local dirs = file.GetDirectories(self._directory)
    if dirs then
        for _, dir in pairs(dirs) do
            local main_file = self._directory .. "/" .. dir .. "/main.xml"
            if io.file_is_readable(main_file) then
                local cfile = io.open(main_file, 'r')
                local data = ScriptSerializer:from_custom_xml(cfile:read("*all"))
                self:LoadConfig(dir, self._directory .. "/" .. dir .. "/", data)
            else
                BeardLib:log("[ERROR] Could not read the main.xml file from " .. self._directory .. "/" .. dir)
            end
        end
    end
end

function FrameworkBase:LoadConfig(name, path, data)
    self._loaded_configs[name] = {data = data, path = path, name = name}

    for _, sub_data in ipairs(data) do
        local cfg_tbl = self._config_calls[sub_data._meta]
        if cfg_tbl then
            cfg_tbl.func(name, path, sub_data)
        else
            BeardLib:log("[ERROR] No Config call for the subtable: " .. sub_data._meta)
        end
    end
end

local load_localization_file = function(path, directory, file)
    local localiz_path = path .. directory .. "/" .. file
    if io.file_is_readable(localiz_path) then
        BeardLib:log("Loaded: " .. localiz_path)
        LocalizationManager:load_localization_file(localiz_path)
        return true
    else
        BeardLib:log("[ERROR] Localization file is not readable by the lua state! File: " .. localiz_path)
        return false
    end
end

function FrameworkBase:LoadLocalizationConfig(name, path, data)
    Hooks:Add("LocalizationManagerPostInit", name .. "ConfigLocalization", function(loc)
        local file_loaded = false

        for i, def in ipairs(data) do
            if Idstring(def.language):key() == SystemInfo:language():key() then
                if load_localization_file(name, data.directory, def.file) then
                    file_loaded = true
                    break
                end
            end
        end

        if not file_loaded and data.default then
            load_localization_file(path, data.directory, data.default)
        end
	end)
end

function FrameworkBase:LoadHooks(name, data)
    local path = self._directory .. "/" .. name .. "/" .. (data.directory and data.directory .. "/" or "")
    local dest_tbl = _posthooks
    for _, hook in ipairs(data) do
        if io.file_is_readable(path .. hook.file) then
            local req_script = hook.source_file:lower()

            dest_tbl[req_script] = dest_tbl[req_script] or {}
            table.insert(dest_tbl[req_script], {
                mod_path = path,
                script = path .. hook.file
            })
        else
            BeardLib:log("[ERROR] Hook file does not exist! File: " .. path .. hook.file)
        end
    end
end
