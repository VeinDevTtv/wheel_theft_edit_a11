Keys = {
    ["ESC"] = 322, ["F1"] = 288, ["F2"] = 289, ["F3"] = 170, ["F5"] = 166, ["F6"] = 167, ["F7"] = 168, ["F8"] = 169, ["F9"] = 56, ["F10"] = 57,
    ["~"] = 243, ["1"] = 157, ["2"] = 158, ["3"] = 160, ["4"] = 164, ["5"] = 165, ["6"] = 159, ["7"] = 161, ["8"] = 162, ["9"] = 163, ["-"] = 84, ["="] = 83, ["BACKSPACE"] = 177,
    ["TAB"] = 37, ["Q"] = 44, ["W"] = 32, ["E"] = 38, ["R"] = 45, ["T"] = 245, ["Y"] = 246, ["U"] = 303, ["P"] = 199, ["["] = 39, ["]"] = 40, ["ENTER"] = 18,
    ["CAPS"] = 137, ["A"] = 34, ["S"] = 8, ["D"] = 9, ["F"] = 23, ["G"] = 47, ["H"] = 74, ["K"] = 311, ["L"] = 182,
    ["LEFTSHIFT"] = 21, ["Z"] = 20, ["X"] = 73, ["C"] = 26, ["V"] = 0, ["B"] = 29, ["N"] = 249, ["M"] = 244, [","] = 82, ["."] = 81,
    ["LEFTCTRL"] = 36, ["LEFTALT"] = 19, ["SPACE"] = 22, ["RIGHTCTRL"] = 70,
    ["HOME"] = 213, ["PAGEUP"] = 10, ["PAGEDOWN"] = 11, ["DELETE"] = 178,
    ["LEFT"] = 174, ["RIGHT"] = 175, ["TOP"] = 27, ["DOWN"] = 173,
    ["NENTER"] = 201, ["N4"] = 108, ["N5"] = 60, ["N6"] = 107, ["N+"] = 96, ["N-"] = 97, ["N7"] = 117, ["N8"] = 61, ["N9"] = 118
}
MISSION_BLIP = nil
MISSION_AREA = nil
sellerBlip = nil
MISSION_ACTIVATED = false
PLAYER_JOB = nil
STORED_WHEELS = {}
WHEEL_PROP = nil
TARGET_VEHICLE = nil
MISSION_BRICKS = {}

-- Variables for ox_target integration
local targetVehicleNetIds = {}
local truckNetId = nil

function StartMission()
    MISSION_ACTIVATED = true

    if Config.spawnPickupTruck.enabled then
        SpawnTruck()
    end

    Citizen.CreateThread(function()
        local sleep = 1500
        local vehicleModel = Config.vehicleModels[math.random(1, #Config.vehicleModels)]
        local missionLocation = Config.missionLocations[math.random(1, #Config.missionLocations)]
        local coords = ModifyCoordinatesWithLimits(missionLocation.x, missionLocation.y, missionLocation.z, missionLocation.h)
        local player = PlayerPedId()
        local blip = Config.missionBlip
        MISSION_BLIP = CreateSellerBlip(vector3(coords.x, coords.y, coords.z), blip.blipIcon, blip.blipColor, 1.0, 1.0, blip.blipLabel)
        MISSION_AREA = AddBlipForRadius(coords.x, coords.y, coords.z, 100.0)
        SetBlipAlpha(MISSION_AREA, 150)
        local vehicle = SpawnMissionVehicle(vehicleModel, missionLocation)
        SetCustomRims(vehicle)
        TARGET_VEHICLE = vehicle

        if Config.enableBlipRoute then
            SetBlipRoute(MISSION_BLIP, true)
        end
        QBCore.Functions.Notify('Your target vehicle\'s plate number: '.. GetVehicleNumberPlateText(vehicle), 'inform', 40000)

        if Config.printLicensePlateToConsole then
            print('Your target vehicle\'s plate number:' .. GetVehicleNumberPlateText(vehicle))
        end

        if Config.debug then
            SetEntityCoords(PlayerPedId(), missionLocation.x + 2.0, missionLocation.y, missionLocation.z, false, false, false, false)
        end

        if not Config.target.enabled then
            while true do
                local playerCoords = GetEntityCoords(player)
                local vehicleCoords = GetEntityCoords(vehicle)
                local distance = #(vehicleCoords - playerCoords)

                if distance < 3.5 then
                    sleep = 1
                    Draw3DText(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 0.5, L('Lift the car to steal wheels'), 4, 0.035, 0.035)

                    if Entity(vehicle).state.IsVehicleRaised then
                        RemoveBlip(MISSION_BLIP)
                        RemoveBlip(MISSION_AREA)
                        StartWheelTheft(vehicle)
                        break
                    end
                else
                    if IsPedDeadOrDying(PlayerPedId(), 1) then
                        RemoveBlip(MISSION_BLIP)
                        RemoveBlip(MISSION_AREA)
                        CancelMission()
                    end
                end

                Citizen.Wait(sleep)
            end
        else
            --AddEntityToTargeting
        end

    end)
end

function StartWheelTheft(vehicle)
    Citizen.Wait(4000)
    local notified = 'waiting'

    -- Register the target vehicle with ox_target if it's enabled
    if Config.target.enabled then
        RegisterTargetVehicleWithOxTarget(vehicle, true)
    end

    while true do
        local sleep = 1000
        local playerId = PlayerPedId()
        local playerCoords = GetEntityCoords(playerId)
        local vehicleCoords = GetEntityCoords(vehicle)
        local distance = #(playerCoords - vehicleCoords)

        if distance < 200 and not WHEEL_PROP then
            local wheelCoords, wheelToPlayerDistance, wheelIndex, isWheelMounted = FindNearestWheel(vehicle)

            if isWheelMounted then
                if not Config.target.enabled then
                    sleep = 1
                    Draw3DText(wheelCoords.x, wheelCoords.y, wheelCoords.z, L('Press ~g~[~w~E~g~]~w~ to start stealing'), 4, 0.035, 0.035)

                    if IsControlJustReleased(0, Keys['E']) then
                        if notified == 'waiting' and IsPoliceNotified() then
                            notified = true

                            if Config.dispatch.notifyThief then
                                StartVehicleAlarm(vehicle)
                            end

                            TriggerDispatch(GetEntityCoords(PlayerPedId()))
                        elseif notified == 'waiting' and not IsPoliceNotified() then
                            notified = false
                        end

                        StartWheelDismount(vehicle, wheelIndex, false, true, false)
                    end
                end
                -- Target implementation is handled by RegisterTargetVehicleWithOxTarget
            end

            -- Check if all wheels are removed
            local allWheelsRemoved = true
            for i=0, 3 do
                local wheelOffset = GetVehicleWheelXOffset(vehicle, i)
                if wheelOffset ~= 9999999.0 then
                    allWheelsRemoved = false
                    break
                end
            end
            
            -- If all wheels are removed and the player is not currently holding a wheel,
            -- we stop the wheel theft loop - the rest will be handled by the finish option in RegisterTargetVehicleWithOxTarget
            if allWheelsRemoved and not WHEEL_PROP then
                QBCore.Functions.Notify('All wheels have been removed. Lower the vehicle to finish.', 'inform', 8000)
                return
            end
        else
            -- Stop wheel theft and cancel mission if player is too far away
            if distance > 300 then
                QBCore.Functions.Notify('You have moved too far from the target vehicle.', 'error', 5000)
                CancelMission()
                return
            end
        end

        Citizen.Wait(sleep)
    end
end

function CanPlayerLowerThisCar()
    local permTable = Config.jackSystem['lower']

    return UseCache('jobCache', function()
        return Contains(permTable.jobs, PLAYER_JOB)
    end, 500)
end

Citizen.CreateThread(function()
    local permTable = Config.jackSystem['lower']

    while true do
        local sleep = 1500
        local player = PlayerPedId()
        local coords = GetEntityCoords(player)

        if permTable.everyone or CanPlayerLowerThisCar() then
            local vehicle, isRaised = NearestVehicleCached(coords, 3.0)

            if vehicle and vehicle ~= TARGET_VEHICLE and isRaised then
                -- Register the vehicle with ox_target if it's enabled
                if Config.target.enabled then
                    RegisterTargetVehicleWithOxTarget(vehicle, false)
                else
                    -- Legacy E key approach
                    sleep = 1
                    local wheelCoords, wheelToPlayerDistance, wheelIndex, isWheelMounted = FindNearestWheel(vehicle)
                    local vehicleCoords = GetEntityCoords(vehicle)

                    if isWheelMounted then
                        Draw3DText(wheelCoords.x, wheelCoords.y, wheelCoords.z + 0.5, L('Press ~g~[~w~E~g~]~w~ to steal this wheel'), 4, 0.065, 0.065)

                        if IsControlJustReleased(0, Keys['E']) then
                            StartWheelDismount(vehicle, wheelIndex, false, true, false, true)
                        end
                    else
                        Draw3DText(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 0.5, L('Press ~g~[~w~E~g~]~w~ to lower this vehicle'), 4, 0.065, 0.065)

                        if IsControlJustReleased(0, Keys['E']) then
                            local lowered = LowerVehicle(false, true)

                            while not lowered do
                                Citizen.Wait(100)
                            end

                            SpawnBricksUnderVehicle(vehicle)
                            break
                        end
                    end
                end
            end
        end

        Citizen.Wait(sleep)
    end
end)

function NearestVehicleCached(coords, radius)
    return UseCache('nearestCacheVehicle', function()
        local vehicle = GetNearestVehicle(coords.x, coords.y, coords.z, radius)

        if vehicle then
            return vehicle, Entity(vehicle).state.IsVehicleRaised
        else
            return vehicle
        end
    end, 500)
end

function StopWheelTheft(vehicle)
    -- With ox_target, we don't need a separate thread as finishing is handled by the target options
    if Config.target.enabled then
        -- The ox_target is already set up in RegisterTargetVehicleWithOxTarget
        -- We just need to make sure the vehicle network ID is tracked for cleanup
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if not Contains(targetVehicleNetIds, netId) then
            table.insert(targetVehicleNetIds, netId)
        end
        return
    end
    
    -- Legacy E key approach
    Citizen.CreateThread(function()
        while true do
            local sleep = 1000
            local player = PlayerPedId()
            local playerCoords = GetEntityCoords(player)
            local vehicleCoords = GetEntityCoords(vehicle)

            if #(vehicleCoords - playerCoords) < 3.5 then
                sleep = 1
                Draw3DText(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z + 0.5, L('Press ~g~[~w~E~g~]~w~ to finish stealing'), 4, 0.035, 0.035)

                if IsControlJustReleased(0, Keys['E']) then
                    local lowered = LowerVehicle()

                    while not lowered do
                        Citizen.Wait(100)
                    end

                    SpawnBricksUnderVehicle(vehicle)
                    TriggerServerEvent('ls_wheel_theft:RetrieveItem', Config.jackStandName)

                    break
                end
            end

            Citizen.Wait(sleep)
        end

        SetEntityAsNoLongerNeeded(vehicle)
    end)
end

function IsPoliceNotified()
    if not Config.dispatch.enabled then
        return false
    end

    local alertChance = Config.dispatch.alertChance
    local random = math.random(1,100)

    if random <= alertChance then
        return true
    else
        return false
    end
end

-- Function to register a target vehicle with ox_target for wheel theft
function RegisterTargetVehicleWithOxTarget(vehicle, isTargetVehicle)
    -- Only register if ox_target is enabled
    if not Config.target.enabled then return end
    
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if Contains(targetVehicleNetIds, netId) then return end -- Already registered
    
    table.insert(targetVehicleNetIds, netId)
    
    -- Define options for the vehicle
    local options = {}
    
    -- If the vehicle is raised, add wheel options
    if Entity(vehicle).state.IsVehicleRaised then
        -- Add wheel options
        local wheelBones = {
            'wheel_lf', -- Left Front
            'wheel_rf', -- Right Front
            'wheel_lr', -- Left Rear
            'wheel_rr'  -- Right Rear
        }
        
        for i, boneName in ipairs(wheelBones) do
            local wheelIndex = i - 1
            local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
            
            if boneIndex ~= -1 then
                table.insert(options, {
                    name = 'ls_wheel_theft:steal_wheel_' .. wheelIndex,
                    icon = 'fas fa-tire',
                    label = 'Steal Wheel',
                    bones = {boneName},
                    canInteract = function()
                        -- Check if the wheel is still mounted
                        local _, _, _, isWheelMounted = FindNearestWheel(vehicle)
                        return isWheelMounted and Entity(vehicle).state.IsVehicleRaised
                    end,
                    onSelect = function()
                        local notified = IsPoliceNotified()
                        
                        if notified and Config.dispatch.notifyThief then
                            StartVehicleAlarm(vehicle)
                            TriggerDispatch(GetEntityCoords(PlayerPedId()))
                        end
                        
                        StartWheelDismount(vehicle, wheelIndex, false, true, false, not isTargetVehicle)
                    end
                })
            end
        end
        
        -- Add lower vehicle option if this is not a target vehicle
        if not isTargetVehicle then
            table.insert(options, {
                name = 'ls_wheel_theft:lower_vehicle',
                icon = 'fas fa-arrow-down',
                label = 'Lower Vehicle',
                distance = 3.0,
                canInteract = function()
                    -- Only show if all wheels are removed
                    local allWheelsRemoved = true
                    for i=0, 3 do
                        local wheelOffset = GetVehicleWheelXOffset(vehicle, i)
                        if wheelOffset ~= 9999999.0 then
                            allWheelsRemoved = false
                            break
                        end
                    end
                    return allWheelsRemoved and Entity(vehicle).state.IsVehicleRaised
                end,
                onSelect = function()
                    local lowered = LowerVehicle(false, true)
                    while not lowered do
                        Citizen.Wait(100)
                    end
                    SpawnBricksUnderVehicle(vehicle)
                end
            })
        end
        
        -- Add finish stealing option if this is a target vehicle
        if isTargetVehicle then
            table.insert(options, {
                name = 'ls_wheel_theft:finish_stealing',
                icon = 'fas fa-check',
                label = 'Finish Stealing',
                distance = 3.0,
                canInteract = function()
                    -- Only show if all wheels are removed
                    local allWheelsRemoved = true
                    for i=0, 3 do
                        local wheelOffset = GetVehicleWheelXOffset(vehicle, i)
                        if wheelOffset ~= 9999999.0 then
                            allWheelsRemoved = false
                            break
                        end
                    end
                    return allWheelsRemoved and Entity(vehicle).state.IsVehicleRaised
                end,
                onSelect = function()
                    local lowered = LowerVehicle()
                    while not lowered do
                        Citizen.Wait(100)
                    end
                    SpawnBricksUnderVehicle(vehicle)
                    TriggerServerEvent('ls_wheel_theft:RetrieveItem', Config.jackStandName)
                    if netId and Contains(targetVehicleNetIds, netId) then
                        exports.ox_target:removeEntity(netId)
                        for i, v in ipairs(targetVehicleNetIds) do
                            if v == netId then
                                table.remove(targetVehicleNetIds, i)
                                break
                            end
                        end
                    end
                end
            })
        end
    end
    
    -- Only add options if we have any
    if #options > 0 then
        exports.ox_target:addEntity(netId, options)
    end
end

-- Function to register truck with ox_target for wheel storage
function RegisterTruckWithOxTarget(vehicle)
    -- Only register if ox_target is enabled and we're holding a wheel
    if not Config.target.enabled or not WHEEL_PROP then return end
    
    -- Get network ID of the truck
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    
    -- Don't register if it's already registered
    if truckNetId == netId then return end
    
    truckNetId = netId
    
    -- Define options for the truck
    local options = {
        {
            name = 'ls_wheel_theft:store_wheel',
            icon = 'fas fa-box',
            label = 'Store Wheel',
            distance = 3.0,
            canInteract = function()
                -- Only show if player is holding a wheel
                return WHEEL_PROP ~= nil
            end,
            onSelect = function()
                local storedWheel = PutWheelInTruckBed(vehicle, #STORED_WHEELS + 1)
                DeleteEntity(WHEEL_PROP)
                ClearPedTasksImmediately(PlayerPedId())
                table.insert(STORED_WHEELS, storedWheel)
                WHEEL_PROP = nil
                
                -- Remove the truck from ox_target as we no longer need it
                if truckNetId then
                    exports.ox_target:removeEntity(truckNetId)
                    truckNetId = nil
                end
            end
        }
    }
    
    -- Add options to the truck
    exports.ox_target:addEntity(netId, options)
end

function BeginWheelLoadingIntoTruck(wheelProp)
    if not Config.target.enabled then
        Citizen.CreateThread(function()
            while true do
                local sleep = 300
                local player = PlayerPedId()
                local playerCoords = GetEntityCoords(player)
                local vehicle = GetNearestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 5.0)

                if vehicle and IsVehicleATruck(vehicle) then
                    sleep = 1
                    local textCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -1.5, 0.2)
                    Draw3DText(textCoords.x, textCoords.y, textCoords.z + 0.5, L('Press ~g~[~w~E~g~]~w~ to store the wheel'), 4, 0.035, 0.035)

                    if IsControlJustReleased(0, Keys['E']) then
                        local storedWheel = PutWheelInTruckBed(vehicle, #STORED_WHEELS + 1)
                        DeleteEntity(wheelProp)
                        ClearPedTasksImmediately(player)
                        table.insert(STORED_WHEELS, storedWheel)
                        WHEEL_PROP = nil

                        return
                    end
                end

                Citizen.Wait(sleep)
            end
        end)
    else
        -- Register the nearest truck with ox_target for wheel storage
        Citizen.CreateThread(function()
            while WHEEL_PROP do
                local sleep = 300
                local player = PlayerPedId()
                local playerCoords = GetEntityCoords(player)
                local vehicle = GetNearestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 5.0)
                
                if vehicle and IsVehicleATruck(vehicle) then
                    local vehicleCoords = GetEntityCoords(vehicle)
                    local distance = #(vehicleCoords - playerCoords)
                    
                    if distance < 5.0 then
                        RegisterTruckWithOxTarget(vehicle)
                    end
                end
                
                Citizen.Wait(sleep)
            end
            
            -- Clean up when wheel is no longer held
            if truckNetId then
                exports.ox_target:removeEntity(truckNetId)
                truckNetId = nil
            end
        end)
    end
end

function EnableWheelTakeOut()
    if not Config.target.enabled then
        Citizen.CreateThread(function()
            local player = PlayerPedId()

            while #STORED_WHEELS > 0 do
                local sleep = 1000
                local playerCoords = GetEntityCoords(player)
                local vehicle = GetNearestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 5.0)
                local vehicleCoords = GetEntityCoords(vehicle)

                if IsVehicleATruck(vehicle) and not IsPedInAnyVehicle(player, true) and #(vehicleCoords - playerCoords) < 3.5 then
                    sleep = 1
                    local textCoords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -1.5, 0.2)
                    Draw3DText(textCoords.x, textCoords.y, textCoords.z + 0.5, L('Press ~g~[~w~H~g~]~w~ to take Wheel out'), 4, 0.035, 0.035)

                    if IsControlJustReleased(0, Keys['H']) and not HOLDING_WHEEL then
                        local wheelProp = PutWheelInHands()
                        HOLDING_WHEEL = wheelProp
                        DeleteEntity(STORED_WHEELS[#STORED_WHEELS])
                        table.remove(STORED_WHEELS, #STORED_WHEELS)
                    end
                end

                Citizen.Wait(sleep)
            end
            
            -- Clean up when no more wheels are stored
            if truckNetId then
                exports.ox_target:removeEntity(truckNetId)
                truckNetId = nil
            end
        end)
    else
        -- Register trucks that have stored wheels with ox_target
        Citizen.CreateThread(function()
            while #STORED_WHEELS > 0 do
                local sleep = 300
                local player = PlayerPedId()
                local playerCoords = GetEntityCoords(player)
                local vehicle = GetNearestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 5.0)
                
                if vehicle and IsVehicleATruck(vehicle) then
                    local vehicleCoords = GetEntityCoords(vehicle)
                    local distance = #(vehicleCoords - playerCoords)
                    
                    if distance < 5.0 and not HOLDING_WHEEL then
                        -- Register the truck for wheel retrieval
                        local netId = NetworkGetNetworkIdFromEntity(vehicle)
                        
                        -- Don't register if it's already registered
                        if truckNetId ~= netId then
                            -- If there was a previously registered truck, remove it
                            if truckNetId then
                                exports.ox_target:removeEntity(truckNetId)
                            end
                            
                            truckNetId = netId
                            
                            -- Define options for the truck
                            local options = {
                                {
                                    name = 'ls_wheel_theft:take_wheel',
                                    icon = 'fas fa-hand-holding',
                                    label = 'Take Wheel Out',
                                    distance = 3.0,
                                    canInteract = function()
                                        -- Only show if player is not holding a wheel and there are wheels stored
                                        return not HOLDING_WHEEL and #STORED_WHEELS > 0
                                    end,
                                    onSelect = function()
                                        if not HOLDING_WHEEL and #STORED_WHEELS > 0 then
                                            local wheelProp = PutWheelInHands()
                                            HOLDING_WHEEL = wheelProp
                                            DeleteEntity(STORED_WHEELS[#STORED_WHEELS])
                                            table.remove(STORED_WHEELS, #STORED_WHEELS)
                                            
                                            -- If there are no more wheels, clean up the target
                                            if #STORED_WHEELS == 0 and truckNetId then
                                                exports.ox_target:removeEntity(truckNetId)
                                                truckNetId = nil
                                            end
                                        end
                                    end
                                }
                            }
                            
                            -- Add options to the truck
                            exports.ox_target:addEntity(netId, options)
                        end
                    end
                end
                
                Citizen.Wait(sleep)
            end
            
            -- Clean up when no more wheels are stored
            if truckNetId then
                exports.ox_target:removeEntity(truckNetId)
                truckNetId = nil
            end
        end)
    end
end

function StartWheelDismount(vehicle, wheelIndex, mount, TaskPlayerGoToWheel, coordsTable, disableWheelProp)
    local success = true
    
    -- Check if bolt minigame resource exists and try to use it
    if GetResourceState('ls_bolt_minigame') == 'started' then
        -- Use pcall to safely try the export
        local status, result = pcall(function() 
            return exports['ls_bolt_minigame']:BoltMinigame(vehicle, wheelIndex, mount, TaskPlayerGoToWheel, coordsTable)
        end)
        
        if status then
            success = result
        else
            -- Export failed, notify and continue
            QBCore.Functions.Notify('Bolt minigame resource error, skipping...', 'primary', 3000)
            -- Still continue with wheel removal
            success = true
        end
    else
        -- Resource not available, just simulate wheel removal
        QBCore.Functions.Notify('Removing wheel...', 'primary', 2000)
        -- Add a small delay to simulate the minigame
        Citizen.Wait(1500)
    end

    if success and not disableWheelProp then
        SetVehicleWheelXOffset(vehicle, wheelIndex, 9999999.0)
        WHEEL_PROP = PutWheelInHands()
        BeginWheelLoadingIntoTruck(WHEEL_PROP)
    end

    if disableWheelProp then
        BreakOffVehicleWheel(vehicle, wheelIndex, false, false, false, false)
    end
end

function IsVehicleATruck(vehicle)
    return UseCache('isVehicleATruck', function()
        local pickupTruckHashes = {
            GetHashKey("bison"),    GetHashKey("bobcatxl"),    GetHashKey("crusader"),
            GetHashKey("dubsta3"),    GetHashKey("rancherxl"),    GetHashKey("sandking"),
            GetHashKey("sandking2"),    GetHashKey("rebel"),    GetHashKey("rebel2"),
            GetHashKey("kamacho"),    GetHashKey("youga2"),    GetHashKey("monster"),
            GetHashKey("bison3"),    GetHashKey("bodhi2"),    GetHashKey("Sadler")
        }

        return Contains(pickupTruckHashes, GetEntityModel(vehicle))
    end, 500)
end

-- Event to lift vehicle using jackstand from inventory
RegisterNetEvent('ls_wheel_theft:LiftVehicle')
AddEventHandler('ls_wheel_theft:LiftVehicle', function()
    -- Debug output to check if the event is triggered
    QBCore.Functions.Notify('Attempting to use jackstand...', 'primary', 2000)
    -- Call the RaiseCar function from jackstand.lua
    RaiseCar()
end)

RegisterNetEvent('ls_wheel_theft:LowerVehicle')
AddEventHandler('ls_wheel_theft:LowerVehicle', function()
    LowerVehicle()
end)

if Config.command.enabled then
    RegisterCommand(Config.command.name, function()
        RaiseCar()
        TriggerServerEvent('ls_wheel_theft:ResetPlayerState', NetworkGetNetworkIdFromEntity(PlayerPedId()))
    end)
end

-- Add a resource stop handler to ensure the work vehicle is cleaned up
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Clean up work vehicle when resource stops
        -- This is a safety measure to prevent vehicles from being left in the world if the script is stopped
        -- Normal despawning should happen through the CancelMission function when players cancel at the NPC
        if WORK_VEHICLE and DoesEntityExist(WORK_VEHICLE) then
            SetEntityAsMissionEntity(WORK_VEHICLE, true, true)
            DeleteVehicle(WORK_VEHICLE)
            WORK_VEHICLE = nil
        end
        
        -- Clean up all ox_target entities
        if Config.target.enabled then
            -- Clean up all registered target vehicles
            for _, netId in ipairs(targetVehicleNetIds) do
                exports.ox_target:removeEntity(netId)
            end
            targetVehicleNetIds = {}
            
            -- Clean up truck if registered
            if truckNetId then
                exports.ox_target:removeEntity(truckNetId)
                truckNetId = nil
            end
        end
    end
end)

-- Add this function to clean up the target vehicle after all wheels are removed
function CleanupMissionVehicle()
    if TARGET_VEHICLE and DoesEntityExist(TARGET_VEHICLE) then
        -- Start a timer to delete the vehicle after 10 seconds
        Citizen.CreateThread(function()
            QBCore.Functions.Notify('Target vehicle will be removed in 10 seconds...', 'primary', 5000)
            
            -- Wait 10 seconds
            Citizen.Wait(10000)
            
            -- Delete the vehicle if it still exists
            if TARGET_VEHICLE and DoesEntityExist(TARGET_VEHICLE) then
                -- Delete all brick props
                if MISSION_BRICKS and #MISSION_BRICKS > 0 then
                    local brickCount = 0
                    for k, brick in pairs(MISSION_BRICKS) do
                        if DoesEntityExist(brick) then
                            DeleteEntity(brick)
                            brickCount = brickCount + 1
                        end
                    end
                    MISSION_BRICKS = {}
                end
                
                SetEntityAsMissionEntity(TARGET_VEHICLE, true, true)
                DeleteVehicle(TARGET_VEHICLE)
                QBCore.Functions.Notify('Target vehicle has been cleaned up', 'success', 3000)
                TARGET_VEHICLE = nil
            end
        end)
    end
end

-- Function to restore wheels on a vehicle for a new mission
function RestoreWheelsForNewMission(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return false
    end
    
    -- Check if any wheels are missing
    local wheelsNeedRestoring = false
    for i=0, 3 do
        local wheelOffset = GetVehicleWheelXOffset(vehicle, i)
        if wheelOffset == 9999999.0 then
            wheelsNeedRestoring = true
            break
        end
    end
    
    if wheelsNeedRestoring then
        -- Restore all wheels to the vehicle
        SetVehicleWheelXOffset(vehicle, 0, -0.88)  -- front left
        SetVehicleWheelXOffset(vehicle, 1, 0.88)   -- front right
        SetVehicleWheelXOffset(vehicle, 2, -0.88)  -- rear left
        SetVehicleWheelXOffset(vehicle, 3, 0.88)   -- rear right
        
        -- Force wheel update
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleTyreFixed(vehicle, 0)
        SetVehicleTyreFixed(vehicle, 1)
        SetVehicleTyreFixed(vehicle, 2)
        SetVehicleTyreFixed(vehicle, 3)
        
        QBCore.Functions.Notify('Vehicle wheels have been restored for the new mission!', 'success', 5000)
        return true
    end
    
    return false
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded')
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    QBCore.Functions.GetPlayerData(function(PlayerData)
        if PlayerData.job then
            PLAYER_JOB = PlayerData.job.name
        end
    end)
end)

-- Function to check if entity is a car
function IsCar(entity)
    if not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then
        return false
    end

    local entityModel = GetEntityModel(entity)
    if IsThisModelACar(entityModel) then
        return true
    else
        return false
    end
end