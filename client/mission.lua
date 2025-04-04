local cooldown = false
local missionPedNetId = nil

function CreateMissionPed()
    local missionTable = Config.missionPeds['mission_ped']
    local ped = SpawnPed(missionTable)
    local blip = missionTable.blip
    local blipCoords = missionTable.location

    if blip.showBlip then
        CreateSellerBlip(GetEntityCoords(ped), blip.blipIcon, blip.blipColor, 1.0, 1.0, blip.blipLabel)
    end
    
    -- Store the ped netId for use with ox_target
    missionPedNetId = NetworkGetNetworkIdFromEntity(ped)
    
    -- Register the ped with ox_target
    RegisterPedWithOxTarget(ped)
end

-- Function bach n'registeri ped f ox_target
function RegisterPedWithOxTarget(ped)
    -- Hna ghadi n'defini options dial ox_target
    local options = {
        {
            name = 'ls_wheel_theft:start_mission',
            icon = 'fas fa-car-burst',
            label = 'Start Wheel Theft Mission',
            canInteract = function()
                -- Only show this option if not in a mission
                return not MISSION_ACTIVATED
            end,
            onSelect = function()
                if not cooldown then
                    SetCooldown(3000)
                    StartMission()
                end
            end
        },
        {
            name = 'ls_wheel_theft:cancel_mission',
            icon = 'fas fa-ban',
            label = 'Cancel Mission',
            canInteract = function()
                -- Only show this option if already in a mission
                return MISSION_ACTIVATED
            end,
            onSelect = function()
                if not cooldown then
                    SetCooldown(3000)
                    CancelMission()
                end
            end
        }
    }
    
    -- Add the options to the entity using ox_target
    -- We use the netId for consistency across the network
    exports.ox_target:addEntity(missionPedNetId, options)
end

-- This function is no longer needed with ox_target, but we'll keep it as a legacy option
-- in case ox_target.enabled is set to false in the config
function EnableMission(missionPed)
    -- Only run this function if ox_target is disabled
    if Config.target.enabled == false then
        Citizen.CreateThread(function()
            while true do
                local sleep = 1000
                local player = PlayerPedId()
                local playerCoords = GetEntityCoords(player)
                local missionPedCoords = GetEntityCoords(missionPed)

                if GetDistanceBetweenCoords(playerCoords.x, playerCoords.y, playerCoords.z, missionPedCoords.x, missionPedCoords.y, missionPedCoords.z, false) < 3.0 then
                    sleep = 1
                    if not MISSION_ACTIVATED then
                        Draw3DText(missionPedCoords.x, missionPedCoords.y, missionPedCoords.z, L('Press ~g~[~w~E~g~]~w~ to start mission'), 4, 0.065, 0.065)

                        if IsControlJustReleased(0, Keys['E']) and not cooldown then
                            SetCooldown(3000)
                            StartMission()
                        end
                    else
                        Draw3DText(missionPedCoords.x, missionPedCoords.y, missionPedCoords.z, L('Press ~g~[~w~E~g~]~w~ to cancel mission'), 4, 0.065, 0.065)

                        if IsControlJustReleased(0, Keys['E']) and not cooldown then
                            SetCooldown(3000)
                            CancelMission()
                        end
                    end

                end
                Citizen.Wait(sleep)
            end
        end)
    end
end

function CancelMission()
    MISSION_ACTIVATED = false

    if MISSION_BLIP and MISSION_AREA then
        RemoveBlip(MISSION_BLIP)
        RemoveBlip(MISSION_AREA)
    end

    -- Despawn the work vehicle if it exists
    -- This ensures the truck is only removed when a player explicitly cancels the mission by speaking to the NPC
    -- The function is defined in truckSpawn.lua and handles vehicle cleanup
    DespawnWorkVehicle()
end

function SetCooldown(time)
    cooldown = true
    Citizen.CreateThread(function()
        Citizen.Wait(time)
        cooldown = false
    end)
end

-- Event to remove the ped from ox_target when the resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Clean up the ped from ox_target when resource stops
        if missionPedNetId then
            -- Remove the entity from ox_target
            exports.ox_target:removeEntity(missionPedNetId)
        end
    end
end)

CreateMissionPed()