-- Multiplayer support for custom jobs, see Classes/Utils/Network.lua.
local Net = BeardLib.Net

local F = table.remove(RequiredScript:split("/"))

if F == "dlcmanager" then
    -- the join request carries the dlcs string, BeardLib adds what it has to it for the host
    local dlcs_string = GenericDLCManager.dlcs_string
    function GenericDLCManager:dlcs_string(...)
        local dlcs = dlcs_string(self, ...)
        local ok, tokens = pcall(Net.Tokens, Net)
        return ok and dlcs .. tokens or dlcs
    end
elseif F == "networkpeer" then
    local send = NetworkPeer.send
    function NetworkPeer:send(func_name, ...)
        if func_name == "join_request_reply" then
            -- the host tells the joiner the running job, one that is unknown would crash the joiner
            local args, n = {...}, select("#", ...)
            local job_id = args[4]
            if type(job_id) == "string" and job_id ~= "" and Net:IsCustomJob(job_id) and not Net:PeerInfo(self).maps[job_id] then
                args[4] = ""
                return send(self, func_name, unpack(args, 1, n))
            end
        end
        return send(self, func_name, ...)
    end
elseif F == "hoststateingame" then
    local on_join_request_received = HostStateInGame.on_join_request_received
    function HostStateInGame:on_join_request_received(data, peer_name, client_preferred_character, dlcs, xuid, peer_level, gameversion, join_attempt_identifier, auth_ticket, sender)
        local ok, reason = pcall(Net.JoinDenyReason, Net, dlcs)
        if ok and reason then
            BeardLib:log("[Network] Denied the join request of '%s': %s", tostring(peer_name), reason)
            -- the vanilla reply "does not own this heist", the joiner is not kicked or banned and may join again later
            self:_send_request_denied(sender, 4, data.local_peer:user_id() or "")
            return
        end
        return on_join_request_received(self, data, peer_name, client_preferred_character, dlcs, xuid, peer_level, gameversion, join_attempt_identifier, auth_ticket, sender)
    end
elseif F == "connectionnetworkhandler" then
    -- The host tells the selected/running job by id. A client that does not have the job yet would crash on it,
    -- instead it gets the job (download) first and then does what the host said.
    local sync_set_selected_job = ConnectionNetworkHandler.sync_set_selected_job
    function ConnectionNetworkHandler:sync_set_selected_job(job_id, difficulty, sender)
        if job_id and job_id ~= "" and not Net:HasJob(job_id) then
            if self._verify_sender(sender) then
                Net._wanted_job = job_id
                tweak_data:set_difficulty(difficulty)
                Net:EnsureJob(job_id, function()
                    if Net._wanted_job == job_id then
                        Net:ApplyEvents(job_id)
                        managers.raid_job:local_set_selected_job(job_id)
                    end
                end)
            end
            return
        end
        Net._wanted_job = nil
        return sync_set_selected_job(self, job_id, difficulty, sender)
    end

    local sync_current_job = ConnectionNetworkHandler.sync_current_job
    function ConnectionNetworkHandler:sync_current_job(job_id, sender)
        if job_id and job_id ~= "" and not Net:HasJob(job_id) then
            if self._verify_sender(sender) then
                Net._wanted_job = job_id
                Net:EnsureJob(job_id, function()
                    if Net._wanted_job == job_id then
                        managers.raid_job:sync_current_job(job_id)
                    end
                end)
            end
            return
        end
        return sync_current_job(self, job_id, sender)
    end

    -- the rolled events of an operation this client does not have yet (it would index a missing operation)
    local sync_randomize_operation = ConnectionNetworkHandler.sync_randomize_operation
    function ConnectionNetworkHandler:sync_randomize_operation(operation_id, string_delimited, sender)
        if operation_id and operation_id ~= "" and not Net:HasJob(operation_id) then
            if self._verify_sender(sender) then
                Net._events[operation_id] = string_delimited
            end
            return
        end
        return sync_randomize_operation(self, operation_id, string_delimited, sender)
    end

    local sync_external_start_mission = ConnectionNetworkHandler.sync_external_start_mission
    function ConnectionNetworkHandler:sync_external_start_mission(mission_id, ...)
        if mission_id and mission_id ~= "" and not Net:HasJob(mission_id) then
            BeardLib:log("[Network] The host started the unknown job '%s', ignored", tostring(mission_id))
            return
        end
        return sync_external_start_mission(self, mission_id, ...)
    end

    local sync_game_settings = ConnectionNetworkHandler.sync_game_settings
    function ConnectionNetworkHandler:sync_game_settings(job_index, ...)
        -- indices of jobs this client does not have
        if job_index and not tweak_data.operations:get_raid_name_from_index(job_index) then
            return
        end
        return sync_game_settings(self, job_index, ...)
    end
elseif F == "networkmatchmakingsteam" then
    -- A joiner downloads a running custom job before the join request is sent. The host publishes the job in the lobby data.
    local join_server = NetworkMatchMakingSTEAM.join_server
    function NetworkMatchMakingSTEAM:join_server(room_id, skip_showing_dialog, ...)
        local args, n = {...}, select("#", ...)
        local ok, took_over = pcall(Net.PreJoin, Net, room_id, function()
            join_server(self, room_id, true, unpack(args, 1, n))
        end)
        if ok and took_over then
            return
        end
        return join_server(self, room_id, skip_showing_dialog, ...)
    end

    local function publish(self)
        local ok, err = pcall(Net.PublishLobby, Net, self)
        if not ok then
            BeardLib:log("[Network] Could not publish the custom job in the lobby: %s", tostring(err))
        end
    end
    local set_attributes = NetworkMatchMakingSTEAM.set_attributes
    function NetworkMatchMakingSTEAM:set_attributes(...)
        local result = set_attributes(self, ...)
        publish(self)
        return result
    end
    local set_job_info_by_current_job = NetworkMatchMakingSTEAM.set_job_info_by_current_job
    function NetworkMatchMakingSTEAM:set_job_info_by_current_job(...)
        local result = set_job_info_by_current_job(self, ...)
        publish(self)
        return result
    end
elseif F == "operationstweakdata" then
    -- The outlaw intel unlocks a random outlaw raid, from what the player who picks the document up has. A custom outlaw
    -- raid is left out while somebody in the lobby could not play it (no BeardLib / no map), the drop would be lost.
    function OperationsTweakData:get_random_unowned_consumable_raid()
        local owned = Global.consumable_missions_manager.inventory
        local list = {}
        for _, id in ipairs(self:get_all_consumable_raids()) do
            if not owned[id] then
                local mission = self.missions[id]
                local ok, vanilla, old, missing = pcall(Net.Blockers, Net, mission.custom and id or nil)
                if not (mission.custom and ok and (#vanilla > 0 or #old > 0 or #missing > 0)) then
                    table.insert(list, id)
                end
            end
        end
        return #list > 0 and list[math.random(1, #list)] or nil
    end
elseif F == "raidjobmanager" then
    -- the host selects a job: not with peers that cannot play it, the others get the job info first
    local set_selected_job = RaidJobManager.set_selected_job
    function RaidJobManager:set_selected_job(job_id, job_data, ...)
        local id = job_id or (job_data and job_data.job_id)
        if id and Net:IsCustomJob(id) and Network:is_server() then
            if not Net:CanSelect(id) then
                return
            end
            for _, peer in ipairs(Net:RemotePeers()) do
                Net:SendJobInfo(id, peer)
            end
        end
        return set_selected_job(self, job_id, job_data, ...)
    end

    -- A client that joins while a job is selected gets it with the state of the session, vanilla would take the unknown job
    -- for granted and crash. It is left out here and set once the job is there (download).
    local sync_load = RaidJobManager.sync_load
    function RaidJobManager:sync_load(data)
        local state = data and data.RaidJobManager
        local wanted, events_index
        if state then
            if state.current_job_id and state.current_job_id ~= "" and not Net:HasJob(state.current_job_id) then
                state.current_job_id, state.current_job_event = nil, nil -- a running job is not joined without it, see Net:JoinDenyReason
            end
            if state.selected_job_id and state.selected_job_id ~= "" and not Net:HasJob(state.selected_job_id) then
                wanted, events_index = state.selected_job_id, state.events_index
                state.selected_job_id, state.events_index = nil, nil
            end
        end
        local result = sync_load(self, data)
        if wanted then
            Net._wanted_job = wanted
            if events_index then
                Net._events[wanted] = table.concat(events_index, "|")
            end
            Net:EnsureJob(wanted, function()
                if Net._wanted_job == wanted then
                    Net:ApplyEvents(wanted)
                    managers.raid_job:local_set_selected_job(wanted)
                end
            end)
        end
        return result
    end

    -- ... and does not start it before everyone has it
    local external_start_mission = RaidJobManager.external_start_mission
    function RaidJobManager:external_start_mission(...)
        local job = self._current_job or self._selected_job
        if job and job.custom and Network:is_server() then
            if not Net:CanStart(job.job_id, function() self:external_start_mission() end) then
                return
            end
        end
        return external_start_mission(self, ...)
    end
end
