local cooldown = false
local missionPedNetId = nil
local missionPedObject = nil

function CreateMissionPed()
    local missionTable = Config.missionPeds['mission_ped']
    
    local ped = SpawnPed(missionTable)
    local blip = missionTable.blip

    if blip.showBlip then
        CreateSellerBlip(GetEntityCoords(ped), blip.blipIcon, blip.blipColor, 1.0, 1.0, blip.blipLabel)
    end
    
    -- Store the ped netId for use with ox_target
    if DoesEntityExist(ped) then
        missionPedNetId = NetworkGetNetworkIdFromEntity(ped)
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
    -- Store the actual ped for removal later
    missionPedObject = ped
    
    -- Initialize mission state if needed
    if LocalPlayer.state.MissionCompleted == nil then
        LocalPlayer.state.MissionCompleted = false
    end
    
    -- Clear any existing targets for this ped to prevent duplicates
    local pedModel = GetEntityModel(ped)
    exports.ox_target:removeModel(pedModel)
    
    if missionPedNetId and missionPedNetId ~= 0 then
        exports.ox_target:removeEntity(missionPedNetId)
    end
    
    -- Define options for ox_target
    local options = {
        {
            name = 'ls_wheel_theft:start_mission',
            icon = 'fas fa-car-burst',
            label = 'Start Wheel Theft Mission',
            canInteract = function()
                return not MISSION_ACTIVATED and not LocalPlayer.state.MissionCompleted
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
                return MISSION_ACTIVATED and not LocalPlayer.state.MissionCompleted
            end,
            onSelect = function()
                if not cooldown then
                    SetCooldown(3000)
                    CancelMission()
                end
            end
        },
        {
            name = 'ls_wheel_theft:complete_mission',
            icon = 'fas fa-check-circle',
            label = 'Complete Mission',
            canInteract = function()
                return LocalPlayer.state.MissionCompleted == true
            end,
            onSelect = function()
                if not cooldown then
                    SetCooldown(3000)
                    FinishMissionCompletely()
                end
            end
        },
        {
            name = 'ls_wheel_theft:new_mission_same_vehicle',
            icon = 'fas fa-redo',
            label = 'New Mission',
            canInteract = function()
                return LocalPlayer.state.MissionCompleted == true
            end,
            onSelect = function()
                if not cooldown then
                    SetCooldown(3000)
                    StartNewMissionWithExistingVehicle()
                end
            end
        }
    }
    
    -- Use model-based targeting (more reliable)
    exports.ox_target:addModel(pedModel, options)
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

    -- Clean up any brick props left
    if MISSION_BRICKS and #MISSION_BRICKS > 0 then
        for _, brick in pairs(MISSION_BRICKS) do
            if DoesEntityExist(brick) then
                DeleteEntity(brick)
            end
        end
        MISSION_BRICKS = {}
    end
end

-- Event to remove the ped from ox_target when the resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Clean up the ped from ox_target when resource stops
        if missionPedObject and DoesEntityExist(missionPedObject) then
            -- Remove the entity from ox_target using the object reference
            exports.ox_target:removeLocalEntity(missionPedObject)
        end
    end
end)

-- Consolidate cooldown function to be used by all scripts
function SetCooldown(time)
    cooldown = true
    Citizen.CreateThread(function()
        Citizen.Wait(time)
        cooldown = false
    end)
end

-- Event handler to refresh mission ped targeting options
RegisterNetEvent('ls_wheel_theft:client:refreshMissionPed')
AddEventHandler('ls_wheel_theft:client:refreshMissionPed', function()
    -- Only process if we have a mission ped and it's valid
    if missionPedObject and DoesEntityExist(missionPedObject) then
        RegisterPedWithOxTarget(missionPedObject)
    end
end)

-- Command for admins to refresh mission ped targeting
RegisterCommand('refreshMissionPed', function()
    if missionPedObject and DoesEntityExist(missionPedObject) then
        TriggerEvent('ls_wheel_theft:client:refreshMissionPed')
    else
        QBCore.Functions.Notify('No mission ped found to refresh', 'error', 5000)
    end
end, false)

-- Function to completely finish the mission and clean up
function FinishMissionCompletely()
    -- Complete the job by cancelling the mission and cleaning up
    MISSION_ACTIVATED = false
    LocalPlayer.state.MissionCompleted = false
    QBCore.Functions.Notify('Job completed successfully! The car has been disposed of.', 'success', 5000)
    
    -- Clean up everything
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
    
    -- Reset any remaining states
    LocalPlayer.state.AlreadyPaid = false
    
    -- Finally remove the target vehicle
    DespawnWorkVehicle()
    
    -- Handle payment logic
    if not LocalPlayer.state.AlreadyPaid then
        TriggerServerEvent('ls_wheel_theft:server:GiveJobBonus')
        LocalPlayer.state.AlreadyPaid = true
    else
        QBCore.Functions.Notify('Mission completed! You already received payment earlier.', 'primary', 5000)
    end

    -- Clean up any brick props left
    if MISSION_BRICKS and #MISSION_BRICKS > 0 then
        for _, brick in pairs(MISSION_BRICKS) do
            if DoesEntityExist(brick) then
                DeleteEntity(brick)
            end
        end
        MISSION_BRICKS = {}
    end
end

-- Function to start a new mission with existing vehicle
function StartNewMissionWithExistingVehicle()
    -- Store the current vehicle before it gets reset
    local currentVehicle = TARGET_VEHICLE
    
    -- Verify vehicle still exists
    if not currentVehicle or not DoesEntityExist(currentVehicle) then
        QBCore.Functions.Notify('The previous vehicle is no longer available. Starting a regular mission.', 'error', 5000)
        FinishMissionCompletely()
        Wait(1000)
        StartMission()
        return
    end
    
    -- Clean up old mission state but keep the vehicle
    MISSION_ACTIVATED = false
    LocalPlayer.state.MissionCompleted = false
    
    -- Clean up blips
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
    
    -- Reset mission-related states
    LocalPlayer.state.AlreadyPaid = false
    
    QBCore.Functions.Notify('Starting new mission using the existing vehicle...', 'primary', 5000)
    
    -- Short delay before starting new mission
    Wait(1000)
    
    -- Start a modified mission that uses the existing vehicle
    StartMissionWithExistingVehicle(currentVehicle)
end

-- Function to start a mission with a pre-existing vehicle
function StartMissionWithExistingVehicle(vehicle)
    MISSION_ACTIVATED = true
    
    -- Verify we have a valid vehicle models array
    if not Config.vehicleModels or #Config.vehicleModels == 0 then
        QBCore.Functions.Notify('ERROR: No vehicle models found in config.', 'error', 5000)
        return
    end
    
    -- Select a random vehicle model from config for mission data
    local vehicleModel = Config.vehicleModels[math.random(1, #Config.vehicleModels)]
    
    -- Restore wheels to the vehicle if any were removed
    RestoreWheelsForNewMission(vehicle)
    
    -- Fix and clean the vehicle
    SetVehicleFixed(vehicle)
    SetVehicleDirtLevel(vehicle, 0.0)
    
    -- Get vehicle position for mission area
    local vehicleCoords = GetEntityCoords(vehicle)
    
    -- Create mission area and blip
    local radius = 100.0 -- Default radius if not defined in config
    if Config.missionArea and Config.missionArea.radius then
        radius = Config.missionArea.radius
    end
    
    MISSION_AREA = AddBlipForRadius(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z, radius)
    
    -- Set blip properties with defaults if config values are missing
    local areaColor = 1 -- Default blue
    if Config.missionArea and Config.missionArea.color then
        areaColor = Config.missionArea.color
    end
    SetBlipColour(MISSION_AREA, areaColor)
    SetBlipAlpha(MISSION_AREA, 80)
    
    -- Create mission vehicle blip
    MISSION_BLIP = AddBlipForEntity(vehicle)
    
    -- Set blip properties with safe fallbacks
    local blipSprite = 225 -- Default car sprite
    local blipColor = 1 -- Default blue
    
    if Config.missionBlip then
        if Config.missionBlip.blipIcon then
            blipSprite = Config.missionBlip.blipIcon
        end
        
        if Config.missionBlip.blipColor then
            blipColor = Config.missionBlip.blipColor
        end
    end
    
    SetBlipSprite(MISSION_BLIP, blipSprite)
    SetBlipColour(MISSION_BLIP, blipColor)
    SetBlipScale(MISSION_BLIP, 1.0)
    SetBlipDisplay(MISSION_BLIP, 2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString('Target Vehicle')
    EndTextCommandSetBlipName(MISSION_BLIP)
    
    -- Set as mission entity to prevent automatic cleanup
    SetEntityAsMissionEntity(vehicle, true, true)
    
    -- Set global vehicle reference for this mission
    TARGET_VEHICLE = vehicle
    
    QBCore.Functions.Notify('New mission started with the same vehicle! Steal its wheels again.', 'success', 8000)
    
    -- Alert police after a delay if that feature is enabled
    if Config.dispatch and Config.dispatch.enabled then
        local delayTime = 30000 -- Default 30 seconds
        if Config.policeCallTime then
            delayTime = Config.policeCallTime
        end
        
        Citizen.CreateThread(function()
            Citizen.Wait(delayTime)
            
            if MISSION_ACTIVATED then
                TriggerDispatch(vehicleCoords)
            end
        end)
    end
end

CreateMissionPed()