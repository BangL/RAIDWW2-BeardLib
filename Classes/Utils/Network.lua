---Multiplayer support for custom jobs.
---
---Peers announce BeardLib (version) and the custom jobs they have in the join request, as tokens in the dlcs string.
---The host knows right when a peer asks to join, so a vanilla client is turned away by the host with the vanilla
---"does not own this heist" reply, before it can receive anything it would crash on (nothing is kicked or banned).
---A peer that has BeardLib but not the job gets the job info through the hidden BeardLib channel as soon as the host
---selects the job, downloads it right then and tells the host when it has it. The host starts the job when all have it.
---
---Hooks: Hooks/Maps/Network.lua
BeardLib.Net = BeardLib.Net or {}
local Net = BeardLib.Net

Net.MIN_VERSION = "5.1.0.0" -- first version with custom jobs
Net.VERSION_TOKEN = "beardlib_"
Net.MAP_TOKEN = "blmap_"
Net.MSG_JOB = "BeardLib_job_info" -- host -> client
Net.MSG_HAVE = "BeardLib_have_job" -- client -> host
Net.MAX_MAP_TOKENS = 40
Net.START_WAIT_TIMEOUT = 300 -- seconds the host waits for downloads

Net._job_info = {} -- client: job id -> info sent by the host
Net._pending = {} -- client: job id -> functions to run once the job is there
Net._asked = {} -- client: job id -> true once the download prompt was shown
Net._events = {} -- client: operation id -> the events the host rolled, kept until the operation is there

local function loc(id, macros)
    return managers.localization:text(id, macros)
end

local function names_of(peers)
    local names = {}
    for _, peer in ipairs(peers) do
        table.insert(names, peer:name())
    end
    return table.concat(names, ", ")
end

---------------------------------------------------------------------------------------------------
-- Capabilities
---------------------------------------------------------------------------------------------------

function Net:IsCustomJob(job_id)
    local missions = tweak_data and tweak_data.operations and tweak_data.operations.missions
    local mission = job_id and missions and missions[tostring(job_id)]
    return type(mission) == "table" and mission.custom == true
end

--- The tokens appended to the dlcs string of the join request.
function Net:Tokens()
    local tokens = {self.VERSION_TOKEN .. tostring(BeardLib.config.version)}
    local count = 0
    for id, mission in pairs(tweak_data.operations.missions) do
        if type(mission) == "table" and mission.custom and not tostring(id):find("%s") then
            count = count + 1
            if count > self.MAX_MAP_TOKENS then
                break -- the host falls back to the info the peers send afterwards
            end
            table.insert(tokens, self.MAP_TOKEN .. id)
        end
    end
    return table.concat(tokens, " ") .. " "
end

--- What a peer announced: beardlib (it has a version that supports custom jobs), version, maps (job id -> true).
function Net:PeerInfo(peer)
    local info = {maps = {}}
    for dlc in pairs(peer._dlcs or {}) do
        local version = dlc:match("^" .. self.VERSION_TOKEN .. "(.+)$")
        if version then
            info.version = version
        else
            local map = dlc:match("^" .. self.MAP_TOKEN .. "(.+)$")
            if map then
                info.maps[map] = true
            end
        end
    end
    for job_id, has in pairs(peer._beardlib_maps or {}) do
        info.maps[job_id] = has or nil
    end
    info.beardlib = info.version ~= nil and not (Version:new(self.MIN_VERSION) > Version:new(info.version))
    return info
end

--- Same as PeerInfo, for the dlcs string of a join request.
function Net:DlcsInfo(dlcs)
    local peer = {_dlcs = {}}
    for _, dlc in ipairs(string.split(dlcs or "", " ")) do
        peer._dlcs[dlc] = true
    end
    return self:PeerInfo(peer)
end

function Net:RemotePeers()
    local session = managers.network and managers.network:session()
    local peers = {}
    if session then
        for _, peer in pairs(session:peers() or {}) do
            table.insert(peers, peer)
        end
    end
    table.sort(peers, function(a, b) return a:id() < b:id() end)
    return peers
end

--- The custom job that is selected (not started yet) or running, and if it is running.
function Net:ActiveCustomJob()
    local raid_job = managers.raid_job
    if not raid_job then
        return
    end
    local current = raid_job:current_job()
    if current and current.custom then
        return current.job_id, true
    end
    local selected = raid_job:selected_job()
    if selected and selected.custom then
        return selected.job_id, false
    end
end

--- Peers that cannot play the job at all (vanilla or too old BeardLib) and peers that do not have it (yet).
function Net:Blockers(job_id)
    local vanilla, old, missing = {}, {}, {}
    for _, peer in ipairs(self:RemotePeers()) do
        local info = self:PeerInfo(peer)
        if not info.version then
            table.insert(vanilla, peer)
        elseif not info.beardlib then
            table.insert(old, peer)
        elseif job_id and not info.maps[job_id] then
            table.insert(missing, peer)
        end
    end
    return vanilla, old, missing
end

function Net:Notify(message)
    QuickDialog({title = loc("custom_map_alert"), message = message}, {})
end

---------------------------------------------------------------------------------------------------
-- Host
---------------------------------------------------------------------------------------------------

--- Why a join request is turned away, nil if it is fine.
function Net:JoinDenyReason(dlcs)
    local job_id, running = self:ActiveCustomJob()
    if not job_id then
        return
    end
    local info = self:DlcsInfo(dlcs)
    if not info.beardlib then
        return "no BeardLib"
    elseif running and not info.maps[job_id] then
        return "missing job" -- cannot download while the job is already running
    end
end

function Net:JobString(job_id)
    local mission = tweak_data.operations.missions[job_id]
    -- an operation has no level, the one of its first event stands for it
    local level_id = mission.level_id
    if not level_id and mission.events_index_template then
        local first = mission.events_index_template[1] and mission.events_index_template[1][1]
        level_id = first and mission.events[first] and mission.events[first].level_id
    end
    local name = managers.localization:to_upper_text(mission.name_id or "")
    local mod = BeardLib.Utils:GetMapByJobId(job_id)
    local update = {}
    if mod then
        local mod_assets = mod:GetModule(ModAssetsModule.type_name)
        if mod_assets and mod_assets._data then
            update = mod_assets._data
        end
    end
    local version = self:MapVersion(job_id)
    local function clean(s)
        return (tostring(s):gsub("[|]", " "))
    end
    return table.concat({
        clean(job_id), clean(level_id), clean(Global.game_settings.difficulty or ""), clean(name),
        clean(update.id or "null"), clean(update.provider or "null"), clean(version or "null")
    }, "|")
end

--- The installed version of the map of a job, nil if it does not say.
function Net:MapVersion(job_id)
    local mod = BeardLib.Utils:GetMapByJobId(job_id)
    local mod_assets = mod and mod:GetModule(ModAssetsModule.type_name)
    local version = mod_assets and mod_assets.version
    return version ~= nil and tostring(version) or nil
end

--- The job is installed, but in another version than the host's.
function Net:IsOutdated(job_id, info)
    local version = self:MapVersion(job_id)
    return info ~= nil and info.version ~= nil and version ~= nil and info.version ~= version
end

function Net:SendJobInfo(job_id, peer)
    if not self:IsCustomJob(job_id) then
        return
    end
    local info = self:PeerInfo(peer)
    if not info.beardlib then
        return
    end
    peer._beardlib_job_sent = job_id
    LuaNetworking:SendToPeer(peer:id(), self.MSG_JOB, self:JobString(job_id))
end

--- Host: the client tells whether it has the job.
function Net:OnHave(sender, data)
    local peer = Network:is_server() and managers.network:session():peer(tonumber(sender))
    if not peer then
        return
    end
    local job_id, has = unpack(string.split(data or "", "|"))
    peer._beardlib_maps = peer._beardlib_maps or {}
    peer._beardlib_maps[job_id] = has == "1"
    peer._beardlib_declined = peer._beardlib_declined or {}
    peer._beardlib_declined[job_id] = has ~= "1" or nil
    local job = tweak_data.operations.missions[job_id]
    if has ~= "1" and job then
        -- the host should not find out when it tries to start: this peer will not be ready for this job
        managers.notification:add_notification({
            id = "beardlib_declined_" .. tostring(peer:id()),
            duration = 10,
            shelf_life = 10,
            text = loc("beardlib_net_declined", {names = peer:name(), job = loc(job.name_id)}),
        })
    end
end

--- Host, every frame: peers that joined (or got the job after joining) get the job info.
function Net:Update(t, dt)
    if not Network or not Network:is_server() or not managers.network or not managers.network:session() then
        return
    end
    if self._next_check and t < self._next_check then
        return
    end
    self._next_check = t + 1
    local job_id = self:ActiveCustomJob()
    if job_id then
        for _, peer in ipairs(self:RemotePeers()) do
            if peer._beardlib_job_sent ~= job_id and peer:synched() then
                self:SendJobInfo(job_id, peer)
            end
        end
    end
end

--- The host wants to select a custom job: false and a message if that is not possible.
function Net:CanSelect(job_id)
    if not Network:is_server() or not self:IsCustomJob(job_id) then
        return true
    end
    local vanilla, old = self:Blockers(nil)
    if #vanilla > 0 or #old > 0 then
        local names = names_of(#vanilla > 0 and vanilla or old)
        local job = loc(tweak_data.operations.missions[job_id].name_id)
        self:Notify(loc(#vanilla > 0 and "beardlib_net_vanilla_peers" or "beardlib_net_old_peers", {names = names, job = job}))
        return false
    end
    return true
end

--- Host, before the job starts: true if everyone can play it. Otherwise it waits for the downloads (with a
--- message) and starts the job once all have it, or tells why it cannot be started.
function Net:CanStart(job_id, start_func)
    if not Network:is_server() or not self:IsCustomJob(job_id) then
        return true
    end
    local vanilla, old, missing = self:Blockers(job_id)
    local job = loc(tweak_data.operations.missions[job_id].name_id)
    if #vanilla > 0 or #old > 0 then
        self:Notify(loc(#vanilla > 0 and "beardlib_net_vanilla_peers" or "beardlib_net_old_peers", {names = names_of(#vanilla > 0 and vanilla or old), job = job}))
        return false
    end
    if #missing == 0 then
        return true
    end
    local declined = {}
    for _, peer in ipairs(missing) do
        if peer._beardlib_declined and peer._beardlib_declined[job_id] then
            table.insert(declined, peer)
        end
    end
    if #declined > 0 then
        self:Notify(loc("beardlib_net_declined", {names = names_of(declined), job = job}))
        return false
    end
    self:WaitForMaps(job_id, start_func)
    return false
end

function Net:WaitForMaps(job_id, start_func)
    if self._waiting == job_id then
        return
    end
    self._waiting = job_id
    local waited = 0
    local function check()
        if self._waiting ~= job_id then
            return -- cancelled, e.g. another job got selected
        end
        local current = self:ActiveCustomJob()
        local _, _, missing = self:Blockers(job_id)
        if current ~= job_id or not Network:is_server() then
            self._waiting = nil
        elseif #missing == 0 then
            self._waiting = nil
            start_func()
        else
            waited = waited + 1
            local declined
            for _, peer in ipairs(missing) do
                declined = declined or (peer._beardlib_declined and peer._beardlib_declined[job_id])
            end
            if declined then
                self._waiting = nil
                self:Notify(loc("beardlib_net_declined", {names = names_of(missing), job = loc(tweak_data.operations.missions[job_id].name_id)}))
            elseif waited > self.START_WAIT_TIMEOUT then
                self._waiting = nil
                self:Notify(loc("beardlib_net_timeout", {names = names_of(missing), job = loc(tweak_data.operations.missions[job_id].name_id)}))
            else
                if waited == 1 or waited % 10 == 0 then
                    managers.notification:add_notification({
                        id = "beardlib_waiting_for_job",
                        duration = 5,
                        shelf_life = 5,
                        text = loc("beardlib_net_waiting", {names = names_of(missing)}),
                    })
                end
                DelayedCalls:Add("BeardLibWaitForJob", 1, check)
            end
        end
    end
    check()
end

---------------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------------

function Net:HasJob(job_id)
    local mission = tweak_data.operations.missions[job_id]
    return mission ~= nil and not mission.stub
end

---------------------------------------------------------------------------------------------------
-- Server browser
---------------------------------------------------------------------------------------------------

Net._stubs = {}

--- The server browser lists a lobby only if it finds the name of its job in the tweak data. A lobby of a custom job
--- that this client does not have is made known with a placeholder of the job (name and event from the lobby), so it is
--- listed and can be joined, the job is downloaded then. Placeholders are no jobs (HasJob), see ClearStubs.
function Net:AddLobbyStubs(lobby_info)
    local missions = tweak_data.operations.missions
    for i, room in ipairs(lobby_info.room_list or {}) do
        local numbers = lobby_info.attribute_list and lobby_info.attribute_list[i] and lobby_info.attribute_list[i].numbers
        local job_id = numbers and numbers[14]
        if type(job_id) == "string" and job_id ~= "" and (not missions[job_id] or missions[job_id].stub) then
            local lobby = Steam and Steam:lobby(room.room_id)
            local value = lobby and lobby:key_value("beardlib_job")
            local custom_id, info = self:ParseJobString(value)
            if custom_id == job_id then
                self:AddStub(job_id, info.name, tonumber(numbers[16]), numbers[1])
            end
        end
    end
end

function Net:AddStub(job_id, name, mission_type, level_id)
    local missions = tweak_data.operations.missions
    local name_id = "beardlib_stub_" .. job_id
    managers.localization:add_localized_strings({[name_id] = name ~= "" and name or job_id})
    local mission = missions[job_id]
    if not mission then
        mission = {stub = true, name_id = name_id, xp = 0, events = {}}
        missions[job_id] = mission
        self._stubs[job_id] = true
    end
    if mission_type == OperationsTweakData.JOB_TYPE_OPERATION and type(level_id) == "string" then
        mission.events[level_id] = {name_id = name_id}
    end
end

--- Removes the placeholders, a real job of the same id is not touched.
function Net:ClearStubs()
    local missions = tweak_data.operations.missions
    for job_id in pairs(self._stubs) do
        if missions[job_id] and missions[job_id].stub then
            missions[job_id] = nil
        end
    end
    self._stubs = {}
end

local function tell_host(job_id, has)
    local session = managers.network and managers.network:session()
    if session and Network:is_client() then
        LuaNetworking:SendToPeer(1, Net.MSG_HAVE, job_id .. "|" .. (has and "1" or "0"))
    end
end

--- Client: the events the host rolled for an operation it does not have yet are set once it is there.
function Net:ApplyEvents(job_id)
    local events = self._events[job_id]
    if events and self:HasJob(job_id) then
        tweak_data.operations:set_operation_indexes_delimited(job_id, events)
    end
    self._events[job_id] = nil
end

--- Client: runs func once the job is available, downloads it first if needed.
function Net:EnsureJob(job_id, func)
    if self:HasJob(job_id) then
        func()
        return
    end
    self._pending[job_id] = self._pending[job_id] or {}
    table.insert(self._pending[job_id], func)
    if self._job_info[job_id] then
        self:AskDownload(job_id)
    end -- else the info is on its way, OnJobInfo asks
end

--- The info of a job as sent by JobString.
function Net:ParseJobString(data)
    local job_id, level_id, difficulty, name, update_id, provider, version = unpack(string.split(data or "", "|"))
    if not job_id or job_id == "" then
        return
    end
    return job_id, {
        level_id = level_id, difficulty = difficulty, name = name,
        version = version and version ~= "null" and version or nil,
        update = update_id and update_id ~= "null" and {id = update_id, provider = provider ~= "null" and provider or nil} or nil,
    }
end

--- Client: the host sent the info of its custom job.
function Net:OnJobInfo(sender, data)
    if tonumber(sender) ~= 1 then
        return -- only the host decides what is played
    end
    local job_id, info = self:ParseJobString(data)
    if not job_id then
        return
    end
    self._job_info[job_id] = info
    if self:HasJob(job_id) and not self:IsOutdated(job_id, info) then
        tell_host(job_id, true)
    elseif self:HasJob(job_id) then
        self:AskUpdate(job_id)
    elseif self._pending[job_id] then
        self:AskDownload(job_id)
    end
end

--- Client: the job is there, but the host has another version. A map that was not loaded in this session is
--- replaced right away. Otherwise the new version is only there after a restart and the host is told that this peer
--- cannot play it for now.
function Net:AskUpdate(job_id)
    local key = job_id .. "|" .. tostring(self._job_info[job_id].version)
    if self._asked[key] then
        return
    end
    self._asked[key] = true
    local info = self._job_info[job_id]
    local function done(loaded, _, reloaded)
        if loaded and not reloaded then
            self:Notify(loc("custom_map_updated_restart"))
        end
        self._asked[key] = nil
        tell_host(job_id, loaded and reloaded or false)
    end
    if not info.update then
        self:Notify(loc("custom_map_missing_updater"))
        done(false)
        return
    end
    BeardLib.Utils.Sync:DownloadMap(info.name, job_id, info.update, done, true)
end

function Net:AskDownload(job_id)
    if self._asked[job_id] then
        return
    end
    self._asked[job_id] = true
    local info = self._job_info[job_id]
    local function done(loaded, declined)
        if loaded and self:HasJob(job_id) then
            tell_host(job_id, true)
            local funcs = self._pending[job_id] or {}
            self._pending[job_id] = nil
            for _, func in ipairs(funcs) do
                func()
            end
        else
            self._asked[job_id] = nil -- ask again if it gets selected again
            self._pending[job_id] = nil
            tell_host(job_id, false)
        end
    end
    if not info.update then
        self:Notify(loc("custom_map_missing_updater"))
        done(false)
        return
    end
    BeardLib.Utils.Sync:DownloadMap(info.name, job_id, info.update, done)
end

---------------------------------------------------------------------------------------------------
-- Joining a running job
---------------------------------------------------------------------------------------------------

--- Host: the running custom job (and how to get it) is part of the lobby data, so a joiner can get the job first.
function Net:PublishLobby(matchmake)
    local attributes = matchmake._lobby_attributes
    if not attributes or not matchmake.lobby_handler then
        return
    end
    local job = managers.raid_job and managers.raid_job:current_job()
    local value = job and job.custom and self:JobString(job.job_id) or ""
    local changed = attributes.beardlib_job ~= value
    attributes.beardlib_job = value
    if changed then
        matchmake.lobby_handler:set_lobby_data(attributes)
    end
end

--- Client, before the join request is sent: if the lobby plays a custom job this client does not have, the job
--- is downloaded first and the join goes on afterwards. Returns true if it took over (continue is called later).
function Net:PreJoin(room_id, continue)
    local lobby = Steam and Steam:lobby(room_id)
    local value = lobby and lobby:key_value("beardlib_job")
    if not value or value == "" or value == "value_missing" or value == "value_pending" then
        return false
    end
    local job_id, info = self:ParseJobString(value)
    local outdated = job_id and self:IsOutdated(job_id, info)
    if not job_id or (self:HasJob(job_id) and not outdated) then
        return false
    end
    managers.system_menu:close("join_server")
    local function done(loaded, notified, reloaded)
        if outdated and loaded and not reloaded then -- the new version is there after a restart
            self:Notify(loc("custom_map_updated_restart"))
            loaded, notified = false, true
        end
        if loaded and self:HasJob(job_id) then
            managers.menu:show_joining_lobby_dialog()
            continue()
        else
            managers.worldcollection.level_transition_in_progress = false
            if not notified then -- two stacked dialogs cannot be closed
                managers.menu:show_does_not_own_heist() -- same as for a host that cannot be joined without the job
            end
        end
    end
    if not info.update then
        self:Notify(loc("custom_map_missing_updater"))
        done(false, true)
    else
        BeardLib.Utils.Sync:DownloadMap(info.name, job_id, info.update, done, outdated)
    end
    return true
end

Hooks:Add("NetworkReceivedData", "BeardLibNetReceived", function(sender, id, data)
    if id == Net.MSG_JOB then
        Net:OnJobInfo(sender, data)
    elseif id == Net.MSG_HAVE then
        Net:OnHave(sender, data)
    end
end)

Hooks:Add("GameSetupUpdate", "BeardLibNetUpdate", ClassClbk(Net, "Update"))
