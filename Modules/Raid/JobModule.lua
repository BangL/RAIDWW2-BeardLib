JobModule = JobModule or BeardLib:ModuleClass("job", ItemModuleBase)
JobModule._loose = true

BeardLib:RegisterModule("Job", JobModule)

local TEXTURE = Idstring("texture")

function JobModule:init(...)
    self.clean_table = table.add(clone(self.clean_table), {
        -- {param = "chain", action = {"number_indexes", "remove_metas"}},
        -- {
        --     param = "chain",
        --     action = function(tbl)
        --         for _, v in pairs(tbl) do
        --             if v.level_id then
        --                 v = BeardLib.Utils:RemoveAllNumberIndexes(v, true)
        --             else
        --                 for _, _v in pairs(v) do
        --                     _v = BeardLib.Utils:RemoveAllNumberIndexes(_v, true)
        --                 end
        --             end
        --         end
        --     end},
        -- {param = "crimenet_callouts", action = "number_indexes"},
        -- {param = "crimenet_videos", action = "number_indexes"},
        -- {param = "payout", action = "number_indexes"},
        -- {param = "contract_cost", action = "number_indexes"},
        -- {param = "experience_mul", action = "number_indexes"},
        -- {param = "min_mission_xp", action = "number_indexes"},
        -- {param = "max_mission_xp", action = "number_indexes"},
        {param = "allowed_gamemodes", action = "number_indexes"}
    })
    return JobModule.super.init(self, ...)
end

function JobModule:AddJobData(operations, tweak_data)
    local id = self._config.id
    local icon_id = "job_"..id
    if self._config.icon and self._config.icon ~= '' then
        tweak_data.hud_icons[icon_id] = {texture = self._config.icon, texture_rect = self._config.icon_rect or false, custom = true}
    else
        local assets_dir = self._mod.AddFiles and self._mod.AddFiles.directory or "assets"
        local ingame_path = Path:Combine("guis/textures/mods/icons", "job_"..self._config.id)

        local icon = Path:Combine(self._mod.ModPath, assets_dir, ingame_path)
        local icon_png = icon..".png"
        local icon_texture = icon..".texture"
        local found_icon
        if FileIO:Exists(icon_png) then
            found_icon = icon_png
        elseif FileIO:Exists(icon_texture) then
            found_icon = icon_texture
        end
        if found_icon then
            BeardLib.Managers.File:AddFile(TEXTURE, Idstring(ingame_path), found_icon)
            tweak_data.hud_icons[icon_id] = {texture = ingame_path, texture_rect = false, custom = true}
        else
            icon_id = nil
        end
    end

    local data = clone(self._config)
    table.merge(data, {
        name_id = data.name_id or ("job_" .. data.id .. "_name"),
        briefing_id = data.brief_id or ("job_" .. data.id .. "_brief"), -- FIXME?
		job_type = data.job_type or OperationsTweakData.JOB_TYPE_RAID,
	    xp = data.xp or 2000,
		loading = data.loading or {},
		photos = data.photos or {},
		events = data.events,
		events_index_template = data.events_index_template,
        mod_path = self._mod.ModPath,
        custom = true
    })

    -- if data.chain then
    --     for _, stage in pairs(data.chain) do
    --         if stage.level_id then
    --             operations.stages[stage.level_id] = stage
    --         else
    --             for _, _stage in pairs(stage) do
    --                 operations.stages[_stage.level_id] = _stage
    --             end
    --         end
    --     end
    -- end
    if self._config.merge_data then
        table.merge(data, BeardLib.Utils:RemoveMetas(self._config.merge_data, true))
    end

    operations.jobs[tostring(self._config.id)] = data

    local id_str = tostring(id)
    if --[[not data.hide_from_crimenet and
            ((data.job_wrapper and #data.job_wrapper > 0) or #data.chain > 0) and]]
            not table.contains(operations._raids_index, id_str) then
        table.insert(operations._raids_index, id_str)
    end
end

function JobModule:RegisterHook()
    if tweak_data and tweak_data.operations then
        self:AddJobData(tweak_data.operations, tweak_data)
        -- tweak_data.operations:set_job_wrappers()
    else
        Hooks:PostHook(OperationsTweakData, "init", self._config.id .. "AddJobData", ClassClbk(self, "AddJobData"))
    end
end