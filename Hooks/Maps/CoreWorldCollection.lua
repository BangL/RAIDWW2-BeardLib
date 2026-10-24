-- Raids started from the camp are streamed in as worlds of the streaming level, see LevelModule:LoadStreamed.
local prepare_world = CoreWorldCollection.prepare_world
function CoreWorldCollection:prepare_world(world, ...)
    local level_data = world and world.level_data
    local level = level_data and level_data.custom and _G.LevelModule and _G.LevelModule.FromWorldDir("levels/" .. tostring(level_data.world_name) .. "/")
    if level and level ~= BeardLib.current_level then
        level:LoadStreamed()
    end
    return prepare_world(self, world, ...)
end
