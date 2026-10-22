-- Custom raids are no part of the mission progression (the unlock cycles are saved in the profile),
-- so they are always unlocked and available on every difficulty, without touching the saved progression.
local function is_custom_mission(job_type, mission_id)
    local mission = tweak_data.operations.missions[mission_id]
    return mission and mission.custom and mission.job_type == job_type
end

local mission_unlocked = ProgressionManager.mission_unlocked
function ProgressionManager:mission_unlocked(job_type, mission_id, ...)
    return is_custom_mission(job_type, mission_id) or mission_unlocked(self, job_type, mission_id, ...)
end

local get_mission_progression = ProgressionManager.get_mission_progression
function ProgressionManager:get_mission_progression(job_type, mission_id, ...)
    if is_custom_mission(job_type, mission_id) then
        return tweak_data:number_of_difficulties(), 0 -- available, completed
    end
    return get_mission_progression(self, job_type, mission_id, ...)
end
