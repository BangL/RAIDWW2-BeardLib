---Registers a custom operation (job_type operation) in tweak_data.operations.missions.
---An operation is a chain of events, every event is a job (see JobModule) of the same project, run one after another
---in the camp and the levels of those jobs:
---    <operation id="my_op"><event job="raid_a"/><event job="raid_b"/></operation>
---Events with the same `row` are alternatives, the game picks one of them every time the operation is started.
OperationModule = OperationModule or BeardLib:ModuleClass("operation", ItemModuleBase)
OperationModule._loose = true

BeardLib:RegisterModule("Operation", OperationModule)

OperationModule.DEFAULT_ICONS = {icon_menu = "op_random_short_lq", icon_hud = "op_random_short_hd"}
OperationModule.DEFAULT_LOADING = {image = "loading_rhinegold_00", text = "menu_ger_oper_rhinegold"}
OperationModule.MAX_PHOTOS = 12
OperationModule.PHOTO_SIZE = {416, 288}

--- The icons of an operation: the list is 56x56 (job_[ID]_menu), the paper and the loading screen 224x224 (job_[ID]_hud).
OperationModule.ICON_SLOTS = {
    {key = "icon_menu", suffix = "_menu", size = 56},
    {key = "icon_hud", suffix = "_hud", size = 224},
}

function OperationModule:init(...)
    self.clean_table = table.add(clone(self.clean_table), {
        {param = "photos", action = "number_indexes"},
    })
    return OperationModule.super.init(self, ...)
end

--- The events of the config as rows: {{job_id, job_id}, {job_id}, ...}
function OperationModule:GetRows()
    local rows, order = {}, {}
    for index, child in ipairs(self._config) do
        if type(child) == "table" and child._meta == "event" then
            local job_id = tostring(child.job or child.id)
            local row = tostring(child.row or ("_" .. index))
            if not rows[row] then
                rows[row] = {}
                table.insert(order, row)
            end
            table.insert(rows[row], job_id)
        end
    end
    local list = {}
    for _, row in ipairs(order) do
        table.insert(list, rows[row])
    end
    return list
end

function OperationModule:FindIcons()
    JobModule.FindIcons(self)
end

function OperationModule:FindPhotos()
    JobModule.FindPhotos(self)
end

function OperationModule:AddIconData(gui)
    JobModule.AddIconData(self, gui)
end

function OperationModule:AddPhotoData(gui)
    JobModule.AddPhotoData(self, gui)
end

--- The job of an event. The modules of a project are not initialized in the order of the main.xml, so the job may not be
--- registered yet: it is registered right away then (its own registration later does the same again).
function OperationModule:GetJob(operations, job_id)
    local job = operations.missions[job_id]
    if type(job) == "table" and job.job_type == OperationsTweakData.JOB_TYPE_RAID then
        return job
    end
    for _, module in pairs(self._mod._modules or {}) do
        if module.type_name == "job" and module._config and tostring(module._config.id) == job_id then
            module:AddJobData(operations)
            return operations.missions[job_id]
        end
    end
    return job
end

function OperationModule:AddOperationData(operations)
    local id = tostring(self._config.id)
    self:FindIcons()
    self:FindPhotos()

    local rows = self:GetRows()
    local events, template = {}, {}
    for _, row in ipairs(rows) do
        local valid = {}
        for _, job_id in ipairs(row) do
            local job = self:GetJob(operations, job_id)
            if events[job_id] then
                -- the events are keyed by their job and the game never picks a job twice, a second one would hang/crash the start
                self:Err("The job '%s' is used by more than one event of the operation '%s', only the first one is used", job_id, id)
            elseif type(job) ~= "table" or job.job_type ~= OperationsTweakData.JOB_TYPE_RAID then
                self:Err("The event '%s' of the operation '%s' is no job (raid) of this project!", job_id, id)
            else
                -- the event is the job itself, only the texts of the progress screens are added
                local event = clone(job)
                event.mission_id = job_id
                event.progress_title_id = event.progress_title_id or event.name_id
                event.progress_text_id = event.progress_text_id or event.briefing_id
                events[job_id] = event
                table.insert(valid, job_id)
            end
        end
        if #valid > 0 then
            table.insert(template, valid)
        end
    end
    if #template == 0 then
        self:Err("The operation '%s' has no valid events, it is not registered", id)
        return
    end

    local data = BeardLib.Utils:RemoveAllNumberIndexes(clone(self._config), true)
    table.merge(data, {
        job_id = id,
        name_id = data.name_id or ("job_" .. id .. "_name"),
        briefing_id = data.brief_id or data.briefing_id or ("job_" .. id .. "_brief"),
        job_type = OperationsTweakData.JOB_TYPE_OPERATION,
        region = data.region or "germany",
        xp = tonumber(data.xp) or 5000,
        camp_objective_id = data.camp_objective_id or "obj_camp_goto_raid",
        loading = data.loading or clone(OperationModule.DEFAULT_LOADING),
        photos = JobModule.GetPhotos(self),
        events = events,
        events_index_template = template,
        -- the events can be played one by one (free play) unless it is switched off
        allow_free_play = data.allow_free_play ~= false and data.allow_free_play ~= "false",
        mod_path = self._mod.ModPath,
        custom = true
    })
    for _, slot in ipairs(self.ICON_SLOTS) do
        local icon = self._icons[slot.key]
        data[slot.key] = data[slot.key] or icon and icon.id or self.DEFAULT_ICONS[slot.key]
    end

    if self._config.merge_data then
        table.merge(data, BeardLib.Utils:RemoveMetas(self._config.merge_data, true))
    end

    operations.missions[id] = data

    if not data.hidden and not table.contains(operations._operations_index, id) then
        table.insert(operations._operations_index, id)
    end
end

function OperationModule:RegisterHook()
    if tweak_data and tweak_data.operations then
        self:AddOperationData(tweak_data.operations)
        self:AddIconData(tweak_data.gui)
        self:AddPhotoData(tweak_data.gui)
    else
        Hooks:PostHook(OperationsTweakData, "init", self._config.id .. "AddOperationData", ClassClbk(self, "AddOperationData"))
        Hooks:PostHook(GuiTweakData, "init", self._config.id .. "AddIconData", ClassClbk(self, "AddIconData"))
        Hooks:PostHook(GuiTweakData, "init", self._config.id .. "AddPhotoData", ClassClbk(self, "AddPhotoData"))
    end
end
