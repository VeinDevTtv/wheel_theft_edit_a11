local cooldown = false
local missionPedNetId = nil
local missionPedObject = nil

function CreateMissionPed()
    local missionTable = Config.missionPeds['mission_ped']
    QBCore.Functions.Notify('Creating mission ped at: ' .. missionTable.location.x .. ', ' .. missionTable.location.y .. ', ' .. missionTable.location.z, 'primary', 5000)
    
    local ped = SpawnPed(missionTable)
    local blip = missionTable.blip
    local blipCoords = missionTable.location

    if blip.showBlip then
        CreateSellerBlip(GetEntityCoords(ped), blip.blipIcon, blip.blipColor, 1.0, 1.0, blip.blipLabel)
    end
    
    -- Store the ped netId for use with ox_target
    if DoesEntityExist(ped) then
        QBCore.Functions.Notify('Mission ped created successfully', 'success', 5000)
        missionPedNetId = NetworkGetNetworkIdFromEntity(ped)
        
        if missionPedNetId == 0 then
            QBCore.Functions.Notify('ERROR: Failed to get network ID for mission ped', 'error', 5000)
        else
            QBCore.Functions.Notify('Mission ped network ID: ' .. missionPedNetId, 'primary', 5000)
        end
    else
        QBCore.Functions.Notify('ERROR: Failed to create mission ped', 'error', 5000)
        return
    end
    
    -- Register the ped with ox_target
    if Config.target.enabled then
        Wait(500) -- Small delay to ensure networking is established
        RegisterPedWithOxTarget(ped)
    else
        -- Legacy system
        EnableMission(ped)
    end
end

-- Function bach n'registeri ped f ox_target
function RegisterPedWithOxTarget(ped)
    -- Debug notification
    QBCore.Functions.Notify('Registering mission NPC with ox_target', 'primary', 1000)
    
    -- Store the actual ped for removal later
    missionPedObject = ped
    
    -- Force checking LocalPlayer.state
    local missionCompleted = LocalPlayer.state.MissionCompleted
    if missionCompleted == nil then
        LocalPlayer.state.MissionCompleted = false
        missionCompleted = false
    end
    
    -- Debug: Show current mission state
    QBCore.Functions.Notify('Current mission state: ' .. tostring(missionCompleted), 'primary', 1000)
    
    -- Clear any existing targets for this ped to prevent duplicates
    local pedModel = GetEntityModel(ped)
    exports.ox_target:removeModel(pedModel)
    
    if missionPedNetId and missionPedNetId ~= 0 then
        exports.ox_target:removeEntity(missionPedNetId)
    end
    
    -- Hna ghadi n'defini options dial ox_target
    local options = {
        {
            name = 'ls_wheel_theft:start_mission',
            icon = 'fas fa-car-burst',
            label = 'Start Wheel Theft Mission',
            canInteract = function()
                -- Only show this option if not in a mission and not completed mission
                local isActive = MISSION_ACTIVATED
                local isCompleted = LocalPlayer.state.MissionCompleted
                
                QBCore.Functions.Notify('Start option check: Active=' .. tostring(isActive) .. ', Completed=' .. tostring(isCompleted), 'primary', 1000)
                
                return not isActive and not isCompleted
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
                -- Only show this option if already in a mission and not completed
                local isActive = MISSION_ACTIVATED 
                local isCompleted = LocalPlayer.state.MissionCompleted
                
                QBCore.Functions.Notify('Cancel option check: Active=' .. tostring(isActive) .. ', Completed=' .. tostring(isCompleted), 'primary', 1000)
                
                return isActive and not isCompleted
            end,
            onSelect = function()
                if not cooldown then
                    SetCooldown(3000)
                    CancelMission()
                end
            end
        },
        {
            name = 'ls_wheel_theft:finish_job',
            icon = 'fas fa-check-circle',
            label = 'Finish Wheel Theft Job',
            canInteract = function()
                -- Only show this option if the mission is completed (wheels sold)
                local isCompleted = LocalPlayer.state.MissionCompleted
                
                -- Force check the state again 
                if isCompleted == nil then
                    isCompleted = false
                end
                
                QBCore.Functions.Notify('Finish option check: Completed=' .. tostring(isCompleted), 'primary', 1000)
                
                return isCompleted == true
            end,
            onSelect = function()
                if not cooldown then
                    SetCooldown(3000)
                    -- Complete the job by cancelling the mission and cleaning up
                    MISSION_ACTIVATED = false
                    LocalPlayer.state.MissionCompleted = false
                    QBCore.Functions.Notify('Job completed successfully! The car has been disposed of.', 'success', 5000)
                    
                    -- Now it's safe to clean up everything
                    if MISSION_BLIP and DoesBlipExist(MISSION_BLIP) then
                        RemoveBlip(MISSION_BLIP)
                        MISSION_BLIP = nil
                    end
                    
                    if MISSION_AREA and DoesBlipExist(MISSION_AREA) then
                        RemoveBlip(MISSION_AREA)
                        MISSION_AREA = nil
                    end
                    
                    -- Remove the return to mission giver blip
                    if LocalPlayer.state.ReturnBlip and DoesBlipExist(LocalPlayer.state.ReturnBlip) then
                        RemoveBlip(LocalPlayer.state.ReturnBlip)
                        LocalPlayer.state.ReturnBlip = nil
                    end
                    
                    -- Remove any other remaining blips
                    local blips = GetActiveBlips()
                    for _, blip in ipairs(blips) do
                        if DoesBlipExist(blip) then
                            RemoveBlip(blip)
                        end
                    end
                    
                    -- Finally remove the target vehicle
                    DespawnWorkVehicle()
                    
                    -- No need to give additional bonus as they've already been paid at the seller
                    -- The state AlreadyPaid is set in selling.lua when the player completes the sale
                    if not LocalPlayer.state.AlreadyPaid then
                        -- Add a bonus reward only if they haven't been paid yet
                        TriggerServerEvent('ls_wheel_theft:server:GiveJobBonus')
                        LocalPlayer.state.AlreadyPaid = true
                    else
                        QBCore.Functions.Notify('Mission completed! You already received payment earlier.', 'primary', 5000)
                    end
                end
            end
        }
    }
    
    -- Choose only ONE registration method - model is more reliable
    exports.ox_target:addModel(pedModel, options)
    
    QBCore.Functions.Notify('NPC registered with ox_target - model: ' .. pedModel, 'success', 3000)
end

-- Helper function to get all active blips
function GetActiveBlips()
    local blips = {}
    for i = 1, 500 do -- Check a reasonable number of blip IDs
        if DoesBlipExist(i) then
            table.insert(blips, i)
        end
    end
    return blips
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
        if missionPedObject and DoesEntityExist(missionPedObject) then
            -- Remove the entity from ox_target using the object reference
            exports.ox_target:removeLocalEntity(missionPedObject)
            QBCore.Functions.Notify('Cleaned up mission ped from ox_target', 'primary', 5000)
        end
    end
end)

-- Debug command to directly start a mission
RegisterCommand('startWheelTheft', function()
    QBCore.Functions.Notify('Starting wheel theft mission via debug command', 'primary', 5000)
    StartMission()
end, false)

-- Debug command to test jackstand functionality directly
RegisterCommand('testJackstand', function()
    -- Spawn a vehicle nearby if none exists
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    local vehicle = GetClosestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 10.0, 0, 71)
    
    if not vehicle or not DoesEntityExist(vehicle) then
        -- No vehicle nearby, spawn one
        QBCore.Functions.Notify('No vehicle found nearby, spawning test vehicle', 'primary', 3000)
        
        local modelHash = GetHashKey('sultanrs') -- Use a car from your config
        
        RequestModel(modelHash)
        local modelTimeout = 10000
        while not HasModelLoaded(modelHash) and modelTimeout > 0 do
            Citizen.Wait(100)
            modelTimeout = modelTimeout - 100
        end
        
        if HasModelLoaded(modelHash) then
            -- Spawn vehicle 5 meters in front of player
            local heading = GetEntityHeading(playerPed)
            local forwardX = math.sin(math.rad(-heading)) * 5.0
            local forwardY = math.cos(math.rad(-heading)) * 5.0
            
            vehicle = CreateVehicle(modelHash, playerCoords.x + forwardX, playerCoords.y + forwardY, playerCoords.z, heading, true, false)
            
            -- Set as mission entity so it can be deleted
            SetEntityAsMissionEntity(vehicle, true, true)
            
            -- Set as target vehicle
            TARGET_VEHICLE = vehicle
            QBCore.Functions.Notify('Test vehicle spawned and set as TARGET_VEHICLE', 'success', 5000)
        else
            QBCore.Functions.Notify('Failed to load vehicle model', 'error', 5000)
            return
        end
    else
        -- Use existing vehicle as target
        TARGET_VEHICLE = vehicle
        QBCore.Functions.Notify('Using nearby vehicle as TARGET_VEHICLE', 'success', 3000)
    end
    
    -- Give player a jackstand
    TriggerServerEvent('QBCore:Server:AddItem', Config.jackStandName, 1)
    QBCore.Functions.Notify('Added a jackstand to your inventory', 'success', 3000)
    
    -- Show instructions
    QBCore.Functions.Notify('Use the jackstand from your inventory near the target vehicle', 'primary', 10000)
end, false)

-- Debug command to show target vehicle location
RegisterCommand('targetVehicleInfo', function()
    if TARGET_VEHICLE then
        local coords = GetEntityCoords(TARGET_VEHICLE)
        QBCore.Functions.Notify('Target vehicle coords: ' .. coords.x .. ', ' .. coords.y .. ', ' .. coords.z, 'primary', 10000)
        -- Set a waypoint to the target vehicle
        SetNewWaypoint(coords.x, coords.y)
    else
        QBCore.Functions.Notify('No target vehicle exists. Start a mission first!', 'error', 5000)
    end
end, false)

-- Event handler to refresh mission ped targeting options
RegisterNetEvent('ls_wheel_theft:client:refreshMissionPed')
AddEventHandler('ls_wheel_theft:client:refreshMissionPed', function(sourcePlayer)
    -- This is called on all clients
    
    -- Only process if we have a mission ped and it's valid
    if missionPedObject and DoesEntityExist(missionPedObject) then
        -- Get the ped model
        local pedModel = GetEntityModel(missionPedObject)
        
        -- Remove existing target options to prevent duplicates
        exports.ox_target:removeModel(pedModel)
        
        -- Re-register the ped with ox_target to refresh options
        Citizen.Wait(500) -- Short delay to ensure cleanup is complete
        RegisterPedWithOxTarget(missionPedObject)
        
        QBCore.Functions.Notify('Mission ped targeting refreshed', 'success', 2000)
    end
end)

-- This command allows admin/developers to manually refresh the mission ped targeting
RegisterCommand('refreshMissionPed', function()
    if missionPedObject and DoesEntityExist(missionPedObject) then
        QBCore.Functions.Notify('Manually refreshing mission ped targeting...', 'primary', 3000)
        TriggerEvent('ls_wheel_theft:client:refreshMissionPed', PlayerId())
    else
        QBCore.Functions.Notify('No mission ped found to refresh', 'error', 3000)
    end
end, false)

CreateMissionPed()