DependenciesModule = DependenciesModule or BeardLib:ModuleClass("Dependencies", ModuleBase)

function DependenciesModule:Load(config)
    config = config or self._config
    local missing_dep = false

    for _, dep in ipairs(config) do
        if dep.name then
            local meta = dep._meta:lower()
            local type = dep.type and dep.type:lower() or "blt"
            if meta == "dependency" then
                if type == "mod_overrides" or type == "map" then
                    local beardlib_check = BeardLib.Utils:ModExists(dep.name)
                    if not beardlib_check then
                        missing_dep = true

                        self:CreateErrorDialog(dep)
                    elseif dep.min_ver and beardlib_check then
                        local beardlib_mod = BeardLib.Utils:FindMod(dep.name)
                        local mod_asset = beardlib_mod:GetModule(ModAssetsModule.type_name)

                        self:CompareVersion(dep, mod_asset and mod_asset.min_ver)
                    end
                elseif type == "blt" then
                    local beardlib_check = BeardLib.Utils:ModExists(dep.name)
                    local blt_check, blt_mod = self:CheckBLTMod(dep.name)

                    if not beardlib_check and not blt_check then
                        missing_dep = true

                        self:CreateErrorDialog(dep)
                    elseif dep.min_ver then
                        if beardlib_check then
                            local beardlib_mod = BeardLib.Utils:FindMod(dep.name)
                            local mod_asset = beardlib_mod:GetModule(ModAssetsModule.type_name)

                            self:CompareVersion(dep, mod_asset and mod_asset.min_ver)
                        elseif blt_mod and blt_mod:GetVersion() then
                            self:CompareVersion(dep, blt_mod:GetVersion())
                        end
                    end
                else
                    self:Err("Dependency for '%s' has an invalid type: '%s'", tostring(self._mod.mod), tostring(type))
                end
            elseif meta == "dependencies" then
                self:Load(dep)
            end
        else
            self:Err("Dependency for '%s' has no name", tostring(self._mod.mod))
        end
    end

    if missing_dep then
        return false
    end
end

function DependenciesModule:CheckBLTMod(name)
    for _, v in ipairs(BLT.Mods.mods) do
        if v:GetName() == name then
            return true, v
        end
    end
end

function DependenciesModule:CompareVersion(dep, mod)
    --Round to get correct versions for 1.1 instead of 1.000001234
    if tonumber(dep.version) then
        dep.version = math.round_with_precision(dep.version, 4)
    end

    if tonumber(mod) then
        mod = math.round_with_precision(mod, 4)
    end

    local dep_version = Version:new(dep.version)
    local mod_version = Version:new(mod)

    if mod_version._value ~= "nil" and dep_version > mod_version then
        self._mod:ModError("The mod requires %s version %s or higher in order to run", tostring(dep.name), tostring(dep_version))
    end
end

function DependenciesModule:CreateErrorDialog(dep)
    if dep.id and dep.provider then
        self:AddDepDownload(dep)
        self._mod:ModError("The mod is missing a dependency: '%s' \nYou can download it through the Beardlib Mods Manager.", tostring(dep.name))
    else
        self._mod:ModError("The mod is missing a dependency: '%s'", tostring(dep.name))
    end
end

function DependenciesModule:AddDepDownload(dep)
    --Default install directories for different mod types.
    local install_directory = {
        blt = "./mods/",
        mod_overrides = "./assets/mod_overrides/",
        map = "./maps/"
    }

    dep.type = dep.type and dep.type:lower() or "blt"

    local config = {
        _meta = "AssetUpdates",
        id = dep.id,
        provider = dep.provider,
        install_directory = dep.install_directory or install_directory[dep.type],
        custom_name = dep.name,
        dont_delete = true
    }

    self._mod:AddModule(config)
end