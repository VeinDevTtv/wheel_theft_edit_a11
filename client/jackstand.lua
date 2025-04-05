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
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    
    -- Increase radius to find nearby vehicles
    local vehicle = nil
    local netId = nil
    
    -- Use a larger radius to find vehicles and check if we're close to the target vehicle first
    if TARGET_VEHICLE and DoesEntityExist(TARGET_VEHICLE) then
        local targetCoords = GetEntityCoords(TARGET_VEHICLE)
        local distance = #(pCoords - targetCoords)
        if distance < 4.0 then
            vehicle = TARGET_VEHICLE
            netId = NetworkGetNetworkIdFromEntity(vehicle)
            QBCore.Functions.Notify('Found target vehicle!', 'success', 2000)
        end
    end
    
    -- If target vehicle not found, check other nearby vehicles
    if not vehicle then
        vehicle = GetClosestVehicle(pCoords.x, pCoords.y, pCoords.z, 4.0, 0, 71)
        if vehicle and DoesEntityExist(vehicle) then
            netId = NetworkGetNetworkIdFromEntity(vehicle)
        end
    end
    
    QBCore.Functions.Notify('Debug: Current Job: ' .. (PLAYER_JOB or "None") .. ' | Target Vehicle Exists: ' .. tostring(TARGET_VEHICLE ~= nil), 'primary', 4000)
    
    if not JobCheck() then
        QBCore.Functions.Notify('Job check failed: You need the right job or job restriction disabled', 'error', 5000)
        return
    end
    
    if not vehicle or not DoesEntityExist(vehicle) then
        QBCore.Functions.Notify('No vehicle found nearby', 'error', 5000)
        return
    end
    
    if not CanRaiseVehicle(vehicle) then
        QBCore.Functions.Notify('You cannot raise this vehicle. Is this the target vehicle?', 'error', 5000)
        return
    end

    if vehicle and IsEntityAVehicle(vehicle) and IsCar(vehicle) and not(IsPedInAnyVehicle(playerPed, false)) and IsVehicleSeatFree(vehicle, -1) and IsVehicleStopped(vehicle) then
        -- Check if vehicle is already raised
        if Entity(vehicle).state.IsVehicleRaised then
            QBCore.Functions.Notify('This vehicle is already raised', 'error', 5000)
            return
        end

        QBCore.Functions.Notify('Starting vehicle lift process...', 'success', 2000)
        
        -- Store whether this is the mission target vehicle
        local isMissionTargetVehicle = (vehicle == TARGET_VEHICLE)
        if isMissionTargetVehicle then
            QBCore.Functions.Notify('This is the mission target vehicle!', 'success', 3000)
            -- Store the info directly on the vehicle entity state
            Entity(vehicle).state.IsMissionTarget = true
        end
        
        -- Use mechanic animation where player lies down to check under the car
        local dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@"
        local anim = "machinic_loop_mechandplayer"
        
        RequestAnimDict(dict)
        local animTimeout = 5000 -- 5 seconds timeout
        
        -- Wait for animation dict to load
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
            
            -- If that also fails, try one more alternative
            if not HasAnimDictLoaded(dict) then
                dict = "amb@prop_human_parking_meter@male@base"
                anim = "base"
                RequestAnimDict(dict)
                
                animTimeout = 5000
                while not HasAnimDictLoaded(dict) and animTimeout > 0 do
                    Citizen.Wait(100)
                    animTimeout = animTimeout - 100
                end
            end
        end
        
        -- Position player near the vehicle
        local vehpos = GetEntityCoords(vehicle)
        local min, max = GetModelDimensions(GetEntityModel(vehicle))
        local width = ((max.x - min.x) / 2) - ((max.x - min.x) / 4)
        local length = ((max.y - min.y) / 2) - ((max.y - min.y) / 4)
        
        -- Position player at the driver side of the vehicle
        local playerPos = vector3(vehpos.x - width - 0.5, vehpos.y, vehpos.z)
        local heading = GetHeadingFromVector_2d(vehpos.x - playerPos.x, vehpos.y - playerPos.y)
        
        -- Make player face the vehicle
        SetEntityHeading(playerPed, heading)
        
        -- Start the animation
        if HasAnimDictLoaded(dict) then
            TaskPlayAnim(playerPed, dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
            FreezeEntityPosition(playerPed, true)
        else
            QBCore.Functions.Notify('Error loading animation, but continuing with lift...', 'error', 3000)
        end
        
        Citizen.CreateThread(function()
            Citizen.Wait(1500) -- Wait for animation to start
            
            local veh = vehicle
            NetworkRequestControlOfEntity(veh)

            local timeout = 2000
            while not NetworkHasControlOfEntity(veh) and timeout > 0 do
                Citizen.Wait(100)
                timeout = timeout - 100
            end

            if not NetworkHasControlOfEntity(veh) then
                QBCore.Functions.Notify('Failed to get control of the vehicle', 'error', 5000)
                ClearPedTasks(playerPed)
                FreezeEntityPosition(playerPed, false)
                return
            end

            local vehpos = GetEntityCoords(veh)
            
            -- Request jackstand model
            local model = 'imp_prop_axel_stand_01a'
            RequestModel(model)

            local modelLoaded = false
            local modelLoadTimeout = 10000 -- 10 seconds timeout
            
            Citizen.CreateThread(function()
                while not modelLoaded and modelLoadTimeout > 0 do
                    modelLoaded = HasModelLoaded(model)
                    if not modelLoaded then
                        Citizen.Wait(100)
                        modelLoadTimeout = modelLoadTimeout - 100
                    end
                end
                
                if not modelLoaded then
                    QBCore.Functions.Notify('Failed to load jackstand model', 'error', 5000)
                    ClearPedTasks(playerPed)
                    FreezeEntityPosition(playerPed, false)
                    return
                end
            end)
            
            while not HasModelLoaded(model) do
                Citizen.Wait(10)
            end

            -- Freeze vehicle to prevent movement during lifting
            FreezeEntityPosition(veh, true)

            -- Calculate positions for jackstands using vehicle dimensions
            local min, max = GetModelDimensions(GetEntityModel(veh))
            local width = ((max.x - min.x) / 2) - ((max.x - min.x) / 3.3)
            local length = ((max.y - min.y) / 2) - ((max.y - min.y) / 3.3)
            local zOffset = 0.5
            
            -- Create a scene where the player appears to be working under the vehicle
            -- Create a realistic delay between placing each jackstand
            
            -- First jackstand (front left)
            local flWheelStand = CreateObject(GetHashKey(model), vehpos.x - width, vehpos.y + length, vehpos.z - zOffset, true, true, true)
            PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
            Citizen.Wait(800)
            
            -- Second jackstand (front right)
            local frWheelStand = CreateObject(GetHashKey(model), vehpos.x + width, vehpos.y + length, vehpos.z - zOffset, true, true, true)
            PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
            Citizen.Wait(800)
            
            -- Third jackstand (rear left)
            local rlWheelStand = CreateObject(GetHashKey(model), vehpos.x - width, vehpos.y - length, vehpos.z - zOffset, true, true, true)
            PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
            Citizen.Wait(800)
            
            -- Fourth jackstand (rear right)
            local rrWheelStand = CreateObject(GetHashKey(model), vehpos.x + width, vehpos.y - length, vehpos.z - zOffset, true, true, true)
            PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
            
            -- Set up animations for the jackstands to look proper under the car
            AttachEntityToEntity(flWheelStand, veh, 0, -width, length, -zOffset, 0.0, 0.0, -90.0, false, false, false, false, 0, true)
            FinishJackstand(flWheelStand)

            AttachEntityToEntity(frWheelStand, veh, 0, width, length, -zOffset, 0.0, 0.0, -90.0, false, false, false, false, 0, true)
            FinishJackstand(frWheelStand)

            AttachEntityToEntity(rlWheelStand, veh, 0, -width, -length, -zOffset, 0.0, 0.0, 90.0, false, false, false, false, 0, true)
            FinishJackstand(rlWheelStand)

            AttachEntityToEntity(rrWheelStand, veh, 0, width, -length, -zOffset, 0.0, 0.0, 90.0, false, false, false, false, 0, true)
            FinishJackstand(rrWheelStand)

            Citizen.Wait(100)
            
            -- Save jacks to state
            TriggerServerEvent('ls_wheel_theft:server:saveJacks', netId, NetworkGetNetworkIdFromEntity(flWheelStand), NetworkGetNetworkIdFromEntity(frWheelStand), NetworkGetNetworkIdFromEntity(rlWheelStand), NetworkGetNetworkIdFromEntity(rrWheelStand), true)

            -- Lift the vehicle gradually with sound effects
            QBCore.Functions.Notify('Lifting vehicle...', 'primary', 3000)
            
            -- Play hydraulic jack sound
            PlaySoundFrontend(-1, "VEHICLES_TRANSIT_HYDRAULIC_UP", "VEHICLES_TRANSIT_SOUND", 0)
            
            local addZ = 0
            while addZ < height do
                addZ = addZ + 0.001
                SetEntityCoordsNoOffset(veh, vehpos.x, vehpos.y, vehpos.z + addZ, true, true, true)
                Citizen.Wait(waitTime)
            end

            -- Attach jackstands to the car
            AttachJackToCar(flWheelStand, veh)
            AttachJackToCar(frWheelStand, veh)
            AttachJackToCar(rlWheelStand, veh)
            AttachJackToCar(rrWheelStand, veh)

            -- Complete the process
            Citizen.Wait(1500)
            
            -- Play sound when jackstand placement is finished
            PlaySoundFrontend(-1, "Place_Prop_Success", "DLC_Dmod_Prop_Editor_Sounds", 0)
            
            -- Let the player finish the animation before standing up
            Citizen.Wait(1000)
            ClearPedTasks(playerPed)
            FreezeEntityPosition(playerPed, false)

            TriggerServerEvent('ls_wheel_theft:server:setIsRaised', netId, true)
            TriggerServerEvent('ls_wheel_theft:server:removeItem', Config.jackStandName, 1)
            QBCore.Functions.Notify('Vehicle raised successfully!', 'success', 5000)
            
            -- Register the vehicle with ox_target if enabled
            if Config.target and Config.target.enabled then
                -- Wait a moment to ensure the vehicle state is updated
                Citizen.Wait(500)
                -- Check if this is the target vehicle or a regular vehicle
                RegisterTargetVehicleWithOxTarget(vehicle)
                QBCore.Functions.Notify('Wheels are now available for theft', 'primary', 3000)
            end
        end)
    else
        if vehicle and not IsCar(vehicle) then
            QBCore.Functions.Notify('This is not a car that can be raised', 'error', 5000)
        elseif vehicle and IsPedInAnyVehicle(playerPed, false) then
            QBCore.Functions.Notify('You cannot be in a vehicle to use the jackstand', 'error', 5000)
        elseif vehicle and not IsVehicleSeatFree(vehicle, -1) then
            QBCore.Functions.Notify('The driver seat must be empty', 'error', 5000)
        elseif vehicle and not IsVehicleStopped(vehicle) then
            QBCore.Functions.Notify('The vehicle must be stopped', 'error', 5000)
        else
            QBCore.Functions.Notify('Unable to use jackstand - unknown reason', 'error', 5000)
        end
    end
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
