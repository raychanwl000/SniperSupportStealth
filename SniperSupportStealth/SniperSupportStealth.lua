-------------------------------------------------
--  Menu Logic
-------------------------------------------------
_G.SniperSupportStealth = _G.SniperSupportStealth or {}
SniperSupportStealth._path = ModPath
SniperSupportStealth._data_path = SavePath .. "snipersupportstealth.txt"
-- num_pagers -> number of pagers allowed.
-- num_pagers_per_player -> maximum number of pagers a single
--  player may use
SniperSupportStealth.settings = {}

--Loads the options from blt
function SniperSupportStealth:Load()
    self.settings["num_pagers"] = 4
    self.settings["num_pagers_per_player"] = 4
    self.settings["enabled"] = true
    self.settings["stealth_kill_enabled"] = true
    self.settings["sniper_equipped"] = false

    local file = io.open(self._data_path, "r")
    if (file) then
        for k, v in pairs(json.decode(file:read("*all"))) do
            self.settings[k] = v
        end
    end
end

--Saves the options
function SniperSupportStealth:Save()
    local file = io.open(self._data_path, "w+")
    if file then
        file:write(json.encode(self.settings))
        file:close()
    end
end

--Loads the data table for the menuing system.  Menus are
--ones based
function SniperSupportStealth:getCompleteTable()
    local tbl = {}
    for i, v in pairs(SniperSupportStealth.settings) do
        if i == "num_pagers" then
            tbl[i] = v + 1
        elseif  i == "num_pagers_per_player" then
            tbl[i] = v + 1
        else
            tbl[i] = v
        end
    end

    return tbl
end

--Sets number of pagers.  Called from the menu system.  Menus are all ones
--based
function setNumPagers(this, item)
    SniperSupportStealth.settings["num_pagers"] = item:value() - 1
end

function setNumPagersPerPlayer(this, item)
    SniperSupportStealth.settings["num_pagers_per_player"] = item:value() - 1
end

function setEnabled(this, item)
    local value = item:value() == "on" and true or false
    SniperSupportStealth.settings["enabled"] = value
end

function setStealthKillEnabled(this, item)
    local value = item:value() == "on" and true or false
    SniperSupportStealth.settings["stealth_kill_enabled"] = value
end

--Load locatization strings
Hooks:Add("LocalizationManagerPostInit", "LocalizationManagerPostInit_SniperSupportStealth", function(loc)
    loc:load_localization_file(SniperSupportStealth._path.."loc/en.txt")
end)

--Set up the menu
Hooks:Add("MenuManagerInitialize", "MenuManagerInitialize_SniperSupportStealth", function(menu_manager)
    MenuCallbackHandler.SniperSupportStealth_setNumPagers = setNumPagers
    MenuCallbackHandler.SniperSupportStealth_setNumPagersPerPlayer = setNumPagersPerPlayer
    MenuCallbackHandler.SniperSupportStealth_enabledToggle = setEnabled
    MenuCallbackHandler.SniperSupportStealth_killPagerEnabledToggle = setStealthKillEnabled

    MenuCallbackHandler.SniperSupportStealth_Close = function(this)
        SniperSupportStealth:Save()
    end

    SniperSupportStealth:Load()
    MenuHelper:LoadFromJsonFile(SniperSupportStealth._path.."options.txt", SniperSupportStealth, SniperSupportStealth:getCompleteTable())
end)

-- gets the number of pagers, triggering a load if necessary.  Called
-- by clients
function getNumPagers()
    if not SniperSupportStealth.settings["num_pagers"] then
        SniperSupportStealth:Load()
    end
    return SniperSupportStealth.settings["num_pagers"]
end

function getNumPagersPerPlayer()
    if not SniperSupportStealth.settings["num_pagers_per_player"] then
        SniperSupportStealth:Load()
    end
    return SniperSupportStealth.settings["num_pagers_per_player"]
end

function isSSPEnabled()
    if not SniperSupportStealth.settings["enabled"] then
        SniperSupportStealth:Load()
    end
    return SniperSupportStealth.settings["enabled"]
end

function isStealthKillEnabled()
    if not SniperSupportStealth.settings["stealth_kill_enabled"] then
        SniperSupportStealth:Load()
    end
    return SniperSupportStealth.settings["stealth_kill_enabled"]
end


-------------------------------------------------
--  function for checking silent kill
-------------------------------------------------
function isEligible()
    -- check primary is sniper or not
    local is_snp = Utils:IsCurrentPrimaryOfCategory( "snp" )
    if not is_snp then return false end
    -- check using sniper or not
    local is_holding_primary = Utils:IsCurrentWeaponPrimary()
    if not is_holding_primary then return false end
    -- check detection risk
    detection_risk_threshold = 60
    detection_risk = managers.blackmarket:get_suspicion_offset_of_local(tweak_data.player.SUSPICION_OFFSET_LERP or 0.75)
    detection_risk = math.round(detection_risk * 100)
    if not (detection_risk > detection_risk_threshold) then return false end

    return true
end

function calcDistance()
    local aimPos = Utils:GetPlayerAimPos( managers.player:player_unit(), 10000 )
    local distance = managers.player:player_unit():position() - aimPos
    -- local farEnough = sqrt(distance[0]*distance[0] + distance[1]*distance[1] + distance[2]*distance[2]) > 30
    return distance.ToString()
end

-------------------------------------------------
--  Handler for damaged received
-------------------------------------------------

if RequiredScript == "lib/units/enemies/cop/copbrain" then
    if not _CopBrain_clbk_damage then
        _CopBrain_clbk_damage = CopBrain._clbk_damage
    end

    function CopBrain:clbk_damage(my_unit, damage_info)
        if _CopBrain_clbk_damage then 
            --this seems to get called on damage but not on death
            --So if we take any non-fatal damage, the pager will go off
            --log ("non-fatal damage")
            self._cop_pager_ready = true
            _CopBrain_clbk_damage(self, my_unit, damage_info)
            --log ("made parent callback")
        end
    end

    if not _CopBrain_clbk_death then
        _CopBrain_clbk_death = CopBrain.clbk_death
    end

    ---------------------------------------------------- only edit this function ------------------------------------------
    function CopBrain:clbk_death(my_unit, damage_info)
        if isSSPEnabled() and isStealthKillEnabled() and isEligible() then
            local head
            if damage_info.col_ray then 
                --the idea was to require a headshot.  It turns out that col_ray is not
                --set when the client takes the shot so I can only do OHKs on clients.
                --I figure to make things fair it should be OHKs for everyone
                --head = self._unit:character_damage()._head_body_name and damage_info.col_ray.body and damage_info.col_ray.body:name() == self._unit:character_damage()._ids_head_body_name
                head = true
            else
                --OHK keeps the pager from going ff
                head = true
            end
            if not head then
                -- log ("enabling pager")
                --not headshots will cause the pager to go off
                self._cop_pager_ready = true
            end
            -- if self._cop_pager_ready then
            --     log("_cop_pager_ready is true")
            -- end

            -- log('sniperEquipped: '..tostring(sniperEquipped(my_unit)))
            -- log(tostring(self._unit:movement():stance_name()))
            -- if self._unit:movement():cool() then
            --     log("unit is cool")
            -- end

            --cool() doesn't work for the camera operator on First World Bank.  For
            --some reason he's in stance "cbt" (and therefore uncool) even if he's not
            --alerted.  I figure this is a bug in the map.
            --if not self._cop_pager_ready and self._unit:movement():cool() then
            if not self._cop_pager_ready and self._unit:movement():stance_name() ~= "hos" then
                --we're dead and the pager is not ready, so delete it
                -- log ("pager disabled")
                self._unit:unit_data().has_alarm_pager = false
            end
        end
        _CopBrain_clbk_death(self, my_unit, damage_info)
    end
end



-------------------------------------------------
--  Setting number of pagers
-------------------------------------------------
if RequiredScript == "lib/units/enemies/cop/copbrain" then
    if not _CopBrain_on_alarm_pager_interaction then
        _CopBrain_on_alarm_pager_interaction = CopBrain.on_alarm_pager_interaction
    end

    --This is called when a player interacts with a pager.  Swap in the
    --correct table before actually running the pager interaction
    function CopBrain:on_alarm_pager_interaction(status, player)
        if isSSPEnabled() then
            if status == "complete" then
                --This is where the pager really runs
                local bluffChance = {}
                local numPagers;
                numPagers = getNumPagers()

                --Track the number of pagers a player has answered in the player
                --object
                if not player:base().num_answered then
                    player:base().num_answered = 0
                end

                --log("NumAnswered" .. tostring(player:base().num_answered))

                --If this player can answer a pager, write up to
                --getNumPagersPerPlayer() 1's into the table, otherwise
                --write all 0's.  This way the real on_alarm_pager_interaction
                --will index into the table as normal
                player:base().num_answered = player:base().num_answered + 1
                local tableValue
                if player:base().num_answered <= getNumPagersPerPlayer() then
                    tableValue = 1
                else
                    tableValue = 0
                end
                for i = 0, ( numPagers - 1), 1 do
                    table.insert(bluffChance, tableValue)
                end
                table.insert(bluffChance, 0)

                tweak_data.player.alarm_pager["bluff_success_chance"] = bluffChance
                tweak_data.player.alarm_pager["bluff_success_chance_w_skill"] = bluffChance
            end
        end
        _CopBrain_on_alarm_pager_interaction(self, status, player)
    end
end

Hooks:Add("NetworkManagerOnPeerAdded", "NetworkManagerOnPeerAdded_SSP", function(peer, peer_id)
    if Network:is_server() and isSSPEnabled() then
        local skEnabled = isStealthKillEnabled()
        local numPagers = getNumPagers()
        local numPerPlayer = getNumPagersPerPlayer()

        DelayedCalls:Add("DelayedSSPAnnounce" .. tostring(peer_id), 2, function()

            local message = "Host is running 'SniperSupportStealth'.  "
            if skEnabled then
                message = message .. "Kills on unalerted guards with sniper do not trigger pagers.  "
            end

            message = message .. "A maximum of " .. tostring(numPagers) .. " pagers are allowed, and each player may answer up to " .. tostring(numPerPlayer) .. " pagers."
            local peer2 = managers.network:session() and managers.network:session():peer(peer_id)
            if peer2 then
                peer2:send("send_chat_message", ChatManager.GAME, message)
            end
        end)
    end
end)


-- function sniperEquipped(my_unit)
--     log("-----sniperEquipped-----")
--     -- local weap_name = self._unit:base():default_weapon_name()
--     local wwap_name2 = my_unit:base():default_weapon_name()
--     -- log("weap_name: " .. tostring(weap_name))
--     log("weap_name2: " .. tostring(weap_name2))
--     log("---sniperEquipped end---")
--     return true
-- end