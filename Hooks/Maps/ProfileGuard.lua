-- Keeps custom jobs and levels out of the saved profile (see the ProfileGuard option): no statistics, progression or
-- breadcrumbs keyed by their ids. Kills, xp and the like are not touched, those are not custom.
-- The data is removed from the profile right when it is put together for saving, wherever it was written. The cache holds
-- references to the live tables of the managers, so the profile gets a scrubbed copy and the running game is left alone.

--- Ids of all custom jobs and levels.
--- @return table ids, table list
function BeardLib:CustomJobIds()
    local ids = {}
    -- only custom entries: a custom job can use a vanilla level (level_id), its id must never be removed
    for id, mission in pairs(tweak_data.operations.missions) do
        if type(mission) == "table" and mission.custom then
            ids[tostring(id)] = true
        end
    end
    for id, level in pairs(tweak_data.levels) do
        if type(level) == "table" and level.custom then
            ids[tostring(id)] = true
        end
    end
    return ids
end

local function is_custom_key(key, ids)
    if ids[key] then
        return true
    end
    -- the keys of the job statistics: [job]_part_2_started, [job]_difficulty_2_completed
    -- (not any key that begins with the id, a short id would hit vanilla keys)
    for id in pairs(ids) do
        if key:sub(1, #id + 6) == id .. "_part_" or key:sub(1, #id + 12) == id .. "_difficulty_" then
            return true
        end
    end
    return false
end

local function scrub(tbl, ids, seen)
    seen[tbl] = true
    local remove, remove_values = {}, {}
    for key, value in pairs(tbl) do
        if type(key) == "string" and is_custom_key(key, ids) then
            table.insert(remove, key)
        elseif type(key) == "number" and type(value) == "string" and ids[value] then
            table.insert(remove_values, key)
        elseif type(value) == "table" and not seen[value] then
            scrub(value, ids, seen)
        end
    end
    for _, key in ipairs(remove) do
        tbl[key] = nil
    end
    table.sort(remove_values, function(a, b) return a > b end)
    for _, index in ipairs(remove_values) do
        if #tbl >= index then
            table.remove(tbl, index)
        else
            tbl[index] = nil
        end
    end
end

--- The save slots of operations (job_manager.slots) hold the whole job as value, not keyed by its id: the slots of custom
--- operations are dropped.
local function scrub_save_slots(data, ids)
    local job_manager = data.job_manager
    if type(job_manager) ~= "table" or type(job_manager.slots) ~= "table" then
        return
    end
    local slots = {}
    for index, slot in pairs(job_manager.slots) do
        local job = type(slot) == "table" and slot.current_job
        if not (type(job) == "table" and ids[tostring(job.job_id)]) then
            slots[index] = slot
        end
    end
    job_manager.slots = slots
end

--- Removes everything keyed by the id of a custom job or level from the given profile data.
function BeardLib:ScrubProfileData(data)
    if type(data) ~= "table" or not self.Options:GetValue("ProfileGuard") then
        return
    end
    local ids = self:CustomJobIds()
    if next(ids) then
        -- the unlocked outlaw raids (custom jobs with consumable="true") are meant to be kept, the game drops the ones whose
        -- job is not there (map removed) when it loads them
        local consumables = data.ConsumableMissionManager
        data.ConsumableMissionManager = nil
        scrub_save_slots(data, ids)
        scrub(data, ids, {})
        data.ConsumableMissionManager = consumables
    end
end

local save_cache = SavefileManager._save_cache
function SavefileManager:_save_cache(slot, ...)
    local result = save_cache(self, slot, ...)
    local meta_data = self:_meta_data(slot)
    if meta_data and type(meta_data.cache) == "table" and BeardLib.Options:GetValue("ProfileGuard") then
        meta_data.cache = deep_clone(meta_data.cache)
        BeardLib:ScrubProfileData(meta_data.cache)
    end
    return result
end
