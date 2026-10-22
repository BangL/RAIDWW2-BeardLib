---Registers a custom raid (job_type raid) in tweak_data.operations.missions.
---A job points at exactly one level (level_id, defaults to the job id), see LevelModule.
JobModule = JobModule or BeardLib:ModuleClass("job", ItemModuleBase)
JobModule._loose = true

BeardLib:RegisterModule("Job", JobModule)

local TEXTURE = Idstring("texture")

JobModule.DEFAULT_ICON = "missions_tutorial"
JobModule.DEFAULT_LOADING = {image = "raid_loading_tutorial", text = "loading_generic"}

function JobModule:init(...)
    self.clean_table = table.add(clone(self.clean_table), {
        {param = "photos", action = "number_indexes"},
        {param = "bounty_filters", action = "number_indexes"},
        {param = "excluded_continents", action = "number_indexes"},
        {param = "progression_groups", action = "number_indexes"},
    })
    return JobModule.super.init(self, ...)
end

---Width and height of a png or a dds/texture file, nil if it cannot be read.
local function image_size(path)
    local file = io.open(path, "rb")
    if not file then
        return
    end
    local head = file:read(32)
    file:close()
    if not head or #head < 32 then
        return
    end
    local function int(offset, big_endian)
        local b1, b2, b3, b4 = head:byte(offset, offset + 3)
        if big_endian then
            return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
        end
        return ((b4 * 256 + b3) * 256 + b2) * 256 + b1
    end
    if head:sub(1, 4) == "\137PNG" then
        return int(17, true), int(21, true)
    elseif head:sub(1, 4) == "DDS " then
        return int(17), int(13) -- width, height
    end
end

--- The three icons of a job. The game shows an icon 1:1 in the size of its texture_rect (nothing is scaled), so each
--- slot has its own image: the list and the HUD are 56x56, the folder on the mission selection is 392x392.
JobModule.ICON_SLOTS = {
    {key = "icon_menu", suffix = "_menu", size = 56},
    {key = "icon_menu_big", suffix = "", size = 392},
    {key = "icon_hud", suffix = "_hud", size = 56},
}

---Finds the icons in the icons folder: job_[ID].png (folder), job_[ID]_menu.png (list), job_[ID]_hud.png (HUD),
---or .texture. An image that is far too big for a small slot is ignored, the slot keeps the default icon.
---The old `icon` (texture path, with `icon_rect`) is the icon of the folder.
function JobModule:FindIcons()
    local id = tostring(self._config.id)
    local assets_dir = self._mod.AddFiles and self._mod.AddFiles.directory or "assets"
    self._icons = {}
    for _, slot in ipairs(self.ICON_SLOTS) do
        local name = "job_" .. id .. slot.suffix
        local ingame_path = Path:Combine("guis/textures/mods/icons", name)
        local base = Path:Combine(self._mod.ModPath, assets_dir, ingame_path)
        local file = FileIO:Exists(base .. ".png") and base .. ".png" or FileIO:Exists(base .. ".texture") and base .. ".texture"
        if file then
            local width, height = image_size(file)
            if slot.size < 100 and width and (width > slot.size * 1.5 or height > slot.size * 1.5) then
                self:Warn("Icon %s is %dx%d but %dx%d is the size of a %s icon, using the default icon", file, width, height, slot.size, slot.key)
            else
                BeardLib.Managers.File:AddFile(TEXTURE, Idstring(ingame_path), file)
                self._icons[slot.key] = {id = name, texture = ingame_path, rect = {0, 0, width or slot.size, height or slot.size}}
            end
        elseif slot.key == "icon_menu_big" and self._config.icon and self._config.icon ~= "" then
            local rect = type(self._config.icon_rect) == "table" and self._config.icon_rect or {0, 0, slot.size, slot.size}
            self._icons[slot.key] = {id = name, texture = self._config.icon, rect = rect}
        end
    end
end

JobModule.PHOTO_SIZE = {416, 288}
JobModule.MAX_PHOTOS = 12

---The intel photos of a job: job_[ID]_photo_[N].png (or .texture), N counting up from 1, in the icons folder.
---Title and description are the strings job_[ID]_photo_[N]_title/_description. Photos of the config (`photos`, ids of
---tweak_data.gui.mission_photos with title_id/description_id) win.
function JobModule:FindPhotos()
    local id = tostring(self._config.id)
    local assets_dir = self._mod.AddFiles and self._mod.AddFiles.directory or "assets"
    self._photos = {}
    for i = 1, self.MAX_PHOTOS do
        local name = "job_" .. id .. "_photo_" .. i
        local ingame_path = Path:Combine("guis/textures/mods/icons", name)
        local base = Path:Combine(self._mod.ModPath, assets_dir, ingame_path)
        local file = FileIO:Exists(base .. ".png") and base .. ".png" or FileIO:Exists(base .. ".texture") and base .. ".texture"
        if not file then
            break
        end
        local width, height = image_size(file)
        BeardLib.Managers.File:AddFile(TEXTURE, Idstring(ingame_path), file)
        table.insert(self._photos, {
            id = name,
            texture = ingame_path,
            rect = {0, 0, width or self.PHOTO_SIZE[1], height or self.PHOTO_SIZE[2]},
            title_id = name .. "_title",
            description_id = name .. "_description"
        })
    end
end

---Photos live in tweak_data.gui.mission_photos
function JobModule:AddPhotoData(gui)
    for _, photo in ipairs(self._photos or {}) do
        gui.mission_photos[photo.id] = {texture = photo.texture, texture_rect = photo.rect, custom = true}
    end
end

---A list from an xml attribute ("a,b,c") or a list that is already one.
local function to_list(value)
    if type(value) == "string" then
        local list = {}
        for item in value:gmatch("[^,%s]+") do
            table.insert(list, item)
        end
        return list
    elseif type(value) == "table" then
        return clone(value)
    end
end

---Icons live in tweak_data.gui.icons, which is built after tweak_data.operations.
function JobModule:AddIconData(gui)
    for _, icon in pairs(self._icons or {}) do
        gui.icons[icon.id] = {texture = icon.texture, texture_rect = icon.rect, custom = true}
    end
end

---The dogtags of a raid: the game hands out a random total between min and max (plus
---diff_bonus per difficulty) over the dogtag units of the level, anything above is removed. Without it nothing is planted.
---A preset (`dogtags="small|medium|large"`, default medium) and/or `dogtags_min/_max/_diff_bonus/_min_dist`.
function JobModule:GetDogtags(operations)
    local config = self._config
    local preset = operations.dogtag_types[tostring(type(config.dogtags) == "string" and config.dogtags or "medium")] or operations.dogtag_types.medium
    local dogtags = clone(type(config.dogtags) == "table" and config.dogtags or preset)
    for _, key in ipairs({"min", "max", "diff_bonus", "min_dist"}) do
        dogtags[key] = tonumber(config["dogtags_" .. key]) or dogtags[key]
    end
    return dogtags
end

---The greed items (the small gold loot) of a raid: a random total between min and max is handed out over the greed
---units of the level, anything above is removed. `greed_items_min`/`greed_items_max`, default is a small raid (gold rush).
JobModule.DEFAULT_GREED_ITEMS = {min = 300, max = 500}

function JobModule:GetGreedItems()
    local config = self._config
    local greed = clone(type(config.greed_items) == "table" and config.greed_items or JobModule.DEFAULT_GREED_ITEMS)
    for _, key in ipairs({"min", "max"}) do
        greed[key] = tonumber(config["greed_items_" .. key]) or greed[key]
    end
    return greed
end

function JobModule:GetPhotos()
    if type(self._config.photos) == "table" and #self._config.photos > 0 then
        return self._config.photos
    end
    local photos = {}
    for _, photo in ipairs(self._photos or {}) do
        table.insert(photos, {photo = photo.id, title_id = photo.title_id, description_id = photo.description_id})
    end
    return photos
end

function JobModule:AddJobData(operations)
    local id = tostring(self._config.id)
    local icon_id = "job_"..id
    self:FindIcons()
    self:FindPhotos()

    local data = clone(self._config)

    -- A loading.png/.texture in the folder of the level is the loading screen of the job,
    -- the screen takes the image from ui/loading_screens/[image].
    local level = LevelModule and LevelModule._by_id and LevelModule._by_id[tostring(data.level_id or id)]
    if not (data.loading and data.loading.image) and level and level._loading_file then
        local image = icon_id
        BeardLib.Managers.File:AddFile(TEXTURE, Idstring("ui/loading_screens/" .. image), level._loading_file)
        data.loading = {image = image, text = data.loading and data.loading.text or JobModule.DEFAULT_LOADING.text}
    end
    table.merge(data, {
        job_id = id,
        level_id = tostring(data.level_id or id),
        name_id = data.name_id or ("job_" .. id .. "_name"),
        briefing_id = data.brief_id or data.briefing_id or ("job_" .. id .. "_brief"),
        job_type = OperationsTweakData.JOB_TYPE_RAID,
        region = data.region or "germany",
        xp = data.xp or 2000,
        music_id = data.music_id or "camp",
        -- the camp objective (go to the mission table) is looked up as [id]_hl/_desc, vanilla only has strings for its own raids
        camp_objective_id = data.camp_objective_id or "obj_camp_goto_raid",
        stealth_description = data.stealth_description or (data.start_in_stealth and OperationsTweakData.RAID_STARTS_STEALTHABLE or OperationsTweakData.RAID_NOT_STEALTHABLE),
        mission_state = data.mission_state or OperationsTweakData.STATE_LOCATION_MISSION_SELECTED,
        loading = data.loading or clone(JobModule.DEFAULT_LOADING),
        photos = self:GetPhotos(),
        dogtags = self:GetDogtags(operations),
        greed_items = self:GetGreedItems(),
        mod_path = self._mod.ModPath,
        custom = true
    })

    -- icon ids of the config (e.g. of a vanilla raid) win, then the images of the job, then the default icon
    -- (menus index tweak_data.gui.icons with these without a nil check)
    for _, slot in ipairs(self.ICON_SLOTS) do
        local icon = self._icons[slot.key]
        data[slot.key] = data[slot.key] or icon and icon.id or JobModule.DEFAULT_ICON
    end

    -- excluded_continents="a,b": continents of the level that are not created when it is played as a raid (vanilla: "operation")
    data.excluded_continents = to_list(self._config.excluded_continents)
    -- bounty_forbid_buffs="a,b": buffs (BuffEffectManager.EFFECT_* values) a bounty challenge card of this raid must not have
    local forbid_buffs = to_list(self._config.bounty_forbid_buffs)
    if forbid_buffs then
        data.bounty_filters = table.merge(type(data.bounty_filters) == "table" and data.bounty_filters or {}, {forbid_buffs = forbid_buffs})
    end

    if self._config.merge_data then
        table.merge(data, BeardLib.Utils:RemoveMetas(self._config.merge_data, true))
    end

    operations.missions[id] = data

    if not data.hidden and not table.contains(operations._raids_index, id) then
        table.insert(operations._raids_index, id)
    end
end

function JobModule:RegisterHook()
    if tweak_data and tweak_data.operations then
        self:AddJobData(tweak_data.operations)
        self:AddIconData(tweak_data.gui)
        self:AddPhotoData(tweak_data.gui)
    else
        Hooks:PostHook(OperationsTweakData, "init", self._config.id .. "AddJobData", ClassClbk(self, "AddJobData"))
        Hooks:PostHook(GuiTweakData, "init", self._config.id .. "AddIconData", ClassClbk(self, "AddIconData"))
        Hooks:PostHook(GuiTweakData, "init", self._config.id .. "AddPhotoData", ClassClbk(self, "AddPhotoData"))
    end
end
