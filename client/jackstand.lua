local waitTime = 5
local height = 0.18
local targetVehicleNetIds = {} -- Initialize at the top of the file to avoid nil references
-----------------------------------------------------------------------------------------------------------------------------------------------------
-- Function to check if vehicle is a car
-----------------------------------------------------------------------------------------------------------------------------------------------------
IsCar = function(veh)
    local vc = GetVehicleClass(veh)
    return (vc >= 0 and vc <= 7) or (vc >= 9 and vc <= 12) or (vc >= 17 and vc <= 20)
end

function CanRaiseVehicle(vehicle)
    local permTable = Config.jackSystem['raise']

    if TARGET_VEHICLE then
        if  vehicle == TARGET_VEHICLE then
            return true
        end
    end

    if permTable.everyone or Contains(permTable.jobs, PLAYER_JOB) then
        return true
    end

    return false
end

function CanLowerVehicle(vehicle)
    local permTable = Config.jackSystem['lower']

    if TARGET_VEHICLE then
        if  vehicle == TARGET_VEHICLE then
            return true
        end
    end

    if permTable.everyone or Contains(permTable.jobs, PLAYER_JOB) then
        return true
    end

    return false
end

function RaiseCar()
    -- Verify player job if jobOnly is enabled
    if Config.job.jobOnly and not JobCheck() then
        QBCore.Functions.Notify(L('job_not_allowed'), 'error', 5000)
        return false
    end
    
    -- Get the vehicle in front of the player
    local player = PlayerPedId()
    local coords = GetEntityCoords(player)
    local vehicle = nil
    
    -- Check if we have a TARGET_VEHICLE first (for mission)
    if TARGET_VEHICLE and DoesEntityExist(TARGET_VEHICLE) then
        local targetCoords = GetEntityCoords(TARGET_VEHICLE)
        if #(coords - targetCoords) < 10.0 then
            vehicle = TARGET_VEHICLE
        else
            QBCore.Functions.Notify(L('vehicle_too_far'), 'error', 5000)
            return false
        end
    else
        -- If no target vehicle or not close enough, try to find any vehicle
        vehicle = GetVehicleInDirection()
        
        if not vehicle then
            QBCore.Functions.Notify(L('no_vehicle_found'), 'error', 5000)
            return false
        end
    end
    
    -- Make sure it's a car
    if not IsCar(vehicle) then
        QBCore.Functions.Notify(L('not_a_car'), 'error', 5000)
        return false
    end
    
    -- Check if player can raise any car or just TARGET_VEHICLE
    if not CanRaiseVehicle(vehicle) then
        QBCore.Functions.Notify(L('not_allowed_raise'), 'error', 5000)
        return false
    end
    
    QBCore.Functions.Notify(L('raising_car'), 'primary', 5000)
    
    TriggerServerEvent('ls_wheel_theft:server:removeItem', Config.jackStandName)
    PlayAnim(Settings.jackUse.animDict, Settings.jackUse.anim, Settings.jackUse.flags)
    AttachJackStandsToVehicle(vehicle)
    
    -- This makes the vehicle float in the air
    Citizen.CreateThread(function()
        -- Wait for animation to complete
        Citizen.Wait(Settings.jackUse.time)
        
        QBCore.Functions.Notify(L('car_raised'), 'success', 5000)
        
        -- Setup target options for the raised vehicle
        RegisterTargetVehicleWithOxTarget(vehicle)
        
        -- Save vehicle state as raised
        local plate = GetVehicleNumberPlateText(vehicle)
        TriggerServerEvent('ls_wheel_theft:server:setIsRaised', NetworkGetNetworkIdFromEntity(vehicle), plate, true)
    end)
    
    return true
end

function FinishJackstand(object)
    local rot = GetEntityRotation(object, 5)
    DetachEntity(object)
    FreezeEntityPosition(object, true)

    local coords = GetEntityCoords(object)
    local _, ground = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, true)
    SetEntityCoords(object, coords.x, coords.y, ground, false, false, false, false)
    PlaceObjectOnGroundProperly_2(object)
    SetEntityRotation(object, rot.x, rot.y, rot.z, 5, 0)
    SetEntityCollision(object, false, true)
end

function AttachJackToCar(object, vehicle)
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, GetEntityCoords(object))

    FreezeEntityPosition(object, false)
    AttachEntityToEntity(object, vehicle, 0, offset, 0.0, 0.0, 90.0, 0, 0, 0, 0, 0, 1)
end

if not targetVehicleNetIds then
    targetVehicleNetIds = {}
end

function RegisterTargetVehicleWithOxTarget(vehicle)
    if not Config.target.enabled then return end
    if not vehicle or not DoesEntityExist(vehicle) then return end
    
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    
    -- Only register if vehicle is raised
    if not Entity(vehicle).state.IsVehicleRaised then
        QBCore.Functions.Notify('Vehicle must be raised to register wheels', 'error', 3000)
        return
    end
    
    -- Clear any existing target options for this vehicle to prevent duplicates
    exports.ox_target:removeEntity(netId)
    
    -- Remove any existing target vehicle from the tracking array if it's the same vehicle
    for i, v in ipairs(targetVehicleNetIds) do
        if v == netId then
            table.remove(targetVehicleNetIds, i)
            break
        end
    end
    
    -- Check if this is the mission target vehicle
    local isTargetVehicle = (vehicle == TARGET_VEHICLE) or Entity(vehicle).state.IsMissionTarget
    
    -- Define wheel bone names and indices
    local wheels = {
        { bone = 'wheel_lf', index = 0, label = 'Steal Front-Left Wheel' },
        { bone = 'wheel_rf', index = 1, label = 'Steal Front-Right Wheel' },
        { bone = 'wheel_lr', index = 2, label = 'Steal Rear-Left Wheel' },
        { bone = 'wheel_rr', index = 3, label = 'Steal Rear-Right Wheel' }
    }
    
    -- Define target options for each wheel
    local options = {}
    for _, wheel in ipairs(wheels) do
        table.insert(options, {
            name = 'wheel_theft_wheel_' .. wheel.index,
            icon = 'fas fa-wrench',
            label = wheel.label,
            bones = { wheel.bone },
            distance = 1.5,
            canInteract = function()
                return Entity(vehicle).state.IsVehicleRaised
            end,
            onSelect = function()
                local coordsTable = nil -- Not needed for this call
                StartWheelDismount(vehicle, wheel.index, false, true, coordsTable, false)
            end
        })
    end
    
    -- For target vehicles, only add the Finish Stealing option
    -- For non-target vehicles, add the simple finish option
    if isTargetVehicle then
        -- This is the target vehicle from the mission
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
                
                -- Remove mission blip and area blip
                if MISSION_BLIP and DoesBlipExist(MISSION_BLIP) then
                    RemoveBlip(MISSION_BLIP)
                    MISSION_BLIP = nil
                end
                
                if MISSION_AREA and DoesBlipExist(MISSION_AREA) then
                    RemoveBlip(MISSION_AREA)
                    MISSION_AREA = nil
                end
                
                -- Remove the vehicle from targeting
                if netId and Contains(targetVehicleNetIds, netId) then
                    exports.ox_target:removeEntity(netId)
                    for i, v in ipairs(targetVehicleNetIds) do
                        if v == netId then
                            table.remove(targetVehicleNetIds, i)
                            break
                        end
                    end
                end
                
                -- Start wheel theft now
                EnableSale()
                
                -- Schedule vehicle cleanup
                CleanupMissionVehicle()
            end
        })
    else
        -- This is a regular vehicle, not the target vehicle
        table.insert(options, {
            name = 'wheel_theft_finish',
            icon = 'fas fa-check',
            label = 'Retrieve Jackstand',
            distance = 2.5,
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
                -- Lower the vehicle and retrieve jackstand
                local lowered = LowerVehicle(false, true)
                Citizen.Wait(1000)
                SpawnBricksUnderVehicle(vehicle)
                TriggerServerEvent('ls_wheel_theft:RetrieveItem', Config.jackStandName)
                
                -- Remove the vehicle from targeting
                if netId then
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
    
    -- Add the options to the vehicle
    exports.ox_target:addEntity(netId, options)
    
    -- Add to tracking table
    table.insert(targetVehicleNetIds, netId)
    
    QBCore.Functions.Notify('Wheels are now ready for theft', 'success', 3000)
end

function LowerVehicle(errorCoords, bypass)
    working = false

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local veh, netId = GetNearestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 5.0)

    if veh and (Entity(veh).state.IsVehicleRaised or Entity(veh).state.spacerOnKqCarLift) then

        if DoesVehicleHaveAllWheels(veh) and not bypass then
            QBCore.Functions.Notify('Finish the job', 'inform', 5000)
            return
        end

        if Entity(veh).state.IsVehicleRaised then
            -- Play the same "lying down" animation as when raising the car
            local dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@"
            local anim = "machinic_loop_mechandplayer"
            
            RequestAnimDict(dict)
            local animTimeout = 5000
            
            while not HasAnimDictLoaded(dict) and animTimeout > 0 do
                Citizen.Wait(100)
                animTimeout = animTimeout - 100
            end
            
            -- Try alternatives if first animation fails to load
            if not HasAnimDictLoaded(dict) then
                dict = "amb@world_human_vehicle_mechanic@male@base"
                anim = "base"
                RequestAnimDict(dict)
                
                animTimeout = 5000
                while not HasAnimDictLoaded(dict) and animTimeout > 0 do
                    Citizen.Wait(100)
                    animTimeout = animTimeout - 100
                end
            end
            
            -- Position player for the animation
            local vehpos = GetEntityCoords(veh)
            local min, max = GetModelDimensions(GetEntityModel(veh))
            local width = ((max.x - min.x) / 2) - ((max.x - min.x) / 4)
            
            -- Position player at driver side
            local heading = GetHeadingFromVector_2d(vehpos.x - playerCoords.x, vehpos.y - playerCoords.y)
            SetEntityHeading(playerPed, heading)
            
            -- Play animation if loaded
            if HasAnimDictLoaded(dict) then
                TaskPlayAnim(playerPed, dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
                FreezeEntityPosition(playerPed, true)
            end
            
            -- Play sounds for removing jackstands
            PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
            Citizen.Wait(1000)

            NetworkRequestControlOfEntity(veh)

            local timeout = 2000
            while not NetworkHasControlOfEntity(veh) and timeout > 0 do
                Citizen.Wait(100)
                timeout = timeout - 100
            end

            local vehpos = GetEntityCoords(veh)

            -- Play hydraulic lowering sound
            PlaySoundFrontend(-1, "VEHICLES_TRANSIT_HYDRAULIC_DOWN", "VEHICLES_TRANSIT_SOUND", 0)
            
            local removeZ = 0
            while removeZ < 0.18 do
                removeZ = removeZ + 0.001
                SetEntityCoordsNoOffset(veh, vehpos.x, vehpos.y, vehpos.z - removeZ, true, true, true)
                Citizen.Wait(waitTime)
            end

            FreezeEntityPosition(veh, true)

            -- Remove jackstands with sound effects
            for i = 4, 1, -1 do
                if Entity(veh).state['jackStand' .. i] then
                    PlaySoundFrontend(-1, "REMOVE_TOOL", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
                    Citizen.Wait(300)
                    TriggerServerEvent('ls_wheel_theft:server:forceDeleteJackStand', (Entity(veh).state['jackStand' .. i]))
                end
            end

            Citizen.Wait(500)
            
            -- Clear animation
            ClearPedTasks(playerPed)
            FreezeEntityPosition(playerPed, false)
            
            FreezeEntityPosition(veh, false)

            TriggerServerEvent('ls_wheel_theft:server:setIsRaised', netId, false)
        else
            TriggerServerEvent('ls_wheel_theft:server:setIsRaised', netId, false)
            FreezeEntityPosition(veh, false)
        end

        return true
    end
end
