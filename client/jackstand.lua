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

-- Helper function for vector to string conversion (used in debug)
function vec2str(vec)
    if not vec then return "nil" end
    return string.format("%.2f, %.2f, %.2f", vec.x, vec.y, vec.z)
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
    
    -- Check if vehicle is already raised
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if Entity(vehicle).state.IsVehicleRaised then
        QBCore.Functions.Notify('Vehicle is already raised', 'error', 5000)
        return false
    end
    
    QBCore.Functions.Notify(L('raising_car'), 'primary', 5000)
    
    -- Remove jackstand item from inventory
    TriggerServerEvent('ls_wheel_theft:server:removeItem', Config.jackStandName)
    
    -- Default animation properties if Settings.jackUse is not defined
    local animDict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@"
    local anim = "machinic_loop_mechandplayer"
    local flags = 1  -- Important: Use flag 1 (non-looping)
    local animTime = 5000 -- 5 seconds for animation
    
    -- Use Settings.jackUse if available
    if Settings.jackUse then
        animDict = Settings.jackUse.animDict or animDict
        anim = Settings.jackUse.anim or anim
        flags = 1  -- Override to always use flag 1 to prevent animation loop
        animTime = Settings.jackUse.time or animTime
    end
    
    -- Store the player ped for use in the thread
    local playerPed = PlayerPedId()
    
    -- Play animation in a non-looping way
    RequestAnimDict(animDict)
    local timeout = 1000
    while not HasAnimDictLoaded(animDict) and timeout > 0 do
        Citizen.Wait(10)
        timeout = timeout - 10
    end
    
    if HasAnimDictLoaded(animDict) then
        -- Use a fixed time animation rather than looping one
        TaskPlayAnim(playerPed, animDict, anim, 8.0, -8.0, animTime, flags, 0, false, false, false)
    else
        QBCore.Functions.Notify('Animation failed to load, continuing...', 'primary', 2000)
    end
    
    -- Attach jack stands to vehicle
    AttachJackStandsToVehicle(vehicle)
    
    -- Handle the rest of the process after animation
    Citizen.CreateThread(function()
        -- Wait for animation to complete
        Citizen.Wait(animTime)
        
        -- Make sure animation is cleared
        ClearPedTasks(playerPed)
        
        QBCore.Functions.Notify(L('car_raised'), 'success', 5000)
        
        -- Wait a moment for entity states to update (important!)
        Citizen.Wait(500)
        
        -- Set the IsVehicleRaised state and store plate for saving
        local plate = GetVehicleNumberPlateText(vehicle)
        TriggerServerEvent('ls_wheel_theft:server:setIsRaised', netId, plate, true)
        
        -- Wait for state to sync
        Citizen.Wait(500)
        
        -- Double-check that state was set
        if not Entity(vehicle).state.IsVehicleRaised then
            -- Force set it again if needed
            TriggerServerEvent('ls_wheel_theft:server:setIsRaised', netId, plate, true)
            Citizen.Wait(200)
        end
        
        -- Verify the state was set properly before registering with target
        if Entity(vehicle).state.IsVehicleRaised then
            -- Setup target options for the raised vehicle
            RegisterTargetVehicleWithOxTarget(vehicle)
        else
            QBCore.Functions.Notify('Failed to set vehicle state. Try again.', 'error', 5000)
        end
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
            return false
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
                TaskPlayAnim(playerPed, dict, anim, 8.0, -8.0, 5000, 1, 0, false, false, false)
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

            -- Get both jackstand bases and extensions
            local jackstands = {}
            for i = 1, 4 do
                if Entity(veh).state['jackStand' .. i] then
                    local jackNetId = Entity(veh).state['jackStand' .. i]
                    local jackEntity = NetworkGetEntityFromNetworkId(jackNetId)
                    if DoesEntityExist(jackEntity) then
                        table.insert(jackstands, {
                            entity = jackEntity,
                            netId = jackNetId,
                            type = "base"
                        })
                    end
                end
            end

            local jackExtensions = {}
            for i = 1, 4 do
                if Entity(veh).state['jackExtension' .. i] then
                    local extensionNetId = Entity(veh).state['jackExtension' .. i]
                    local extensionEntity = NetworkGetEntityFromNetworkId(extensionNetId)
                    if DoesEntityExist(extensionEntity) then
                        table.insert(jackExtensions, {
                            entity = extensionEntity,
                            netId = extensionNetId,
                            type = "extension"
                        })
                    end
                end
            end

            -- Play hydraulic lowering sound
            PlaySoundFrontend(-1, "VEHICLES_TRANSIT_HYDRAULIC_DOWN", "VEHICLES_TRANSIT_SOUND", 0)
            
            -- Create retraction animation for jackstands
            local targetHeight = 0.18
            local currentHeight = targetHeight
            local increment = 0.001
            
            while currentHeight > 0 do
                -- Lower the vehicle gradually
                currentHeight = currentHeight - increment
                SetEntityCoordsNoOffset(veh, vehpos.x, vehpos.y, vehpos.z - (targetHeight - currentHeight), true, true, true)
                
                -- Calculate extension offset for the retracting parts
                local extensionOffset = -0.5 - currentHeight
                
                -- Update extension positions to simulate retracting
                for i, extension in ipairs(jackExtensions) do
                    local extensionEntity = extension.entity
                    local xOffset, yOffset = 0, 0
                    local rot = 0
                    
                    if i == 1 then -- Front left
                        xOffset = -((max.x - min.x) / 2) + ((max.x - min.x) / 3.3)
                        yOffset = ((max.y - min.y) / 2) - ((max.y - min.y) / 3.3)
                        rot = GetEntityHeading(veh) - 90.0
                    elseif i == 2 then -- Front right
                        xOffset = ((max.x - min.x) / 2) - ((max.x - min.x) / 3.3)
                        yOffset = ((max.y - min.y) / 2) - ((max.y - min.y) / 3.3)
                        rot = GetEntityHeading(veh) - 90.0
                    elseif i == 3 then -- Rear left
                        xOffset = -((max.x - min.x) / 2) + ((max.x - min.x) / 3.3)
                        yOffset = -((max.y - min.y) / 2) + ((max.y - min.y) / 3.3)
                        rot = GetEntityHeading(veh) + 90.0
                    elseif i == 4 then -- Rear right
                        xOffset = ((max.x - min.x) / 2) - ((max.x - min.x) / 3.3)
                        yOffset = -((max.y - min.y) / 2) + ((max.y - min.y) / 3.3)
                        rot = GetEntityHeading(veh) + 90.0
                    end
                    
                    -- Update extension position with vehicle movement
                    AttachEntityToEntity(extensionEntity, veh, 0, xOffset, yOffset, extensionOffset, 0.0, 0.0, rot, false, false, false, false, 0, true)
                end
                
                -- Add hydraulic sound effects at intervals
                if math.abs(currentHeight - 0.05) < 0.003 or math.abs(currentHeight - 0.1) < 0.003 or math.abs(currentHeight - 0.15) < 0.003 then
                    PlaySoundFrontend(-1, "JACK_VEHICLE", "HUD_MINI_GAME_SOUNDSET", 0)
                end
                
                Citizen.Wait(waitTime)
            end

            -- Set final position
            SetEntityCoordsNoOffset(veh, vehpos.x, vehpos.y, vehpos.z - targetHeight, true, true, true)
            
            -- Play final sound effect
            PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", 0)
            
            -- Freeze vehicle temporarily
            FreezeEntityPosition(veh, true)

            -- First, remove the extension parts
            for i, extension in ipairs(jackExtensions) do
                PlaySoundFrontend(-1, "REMOVE_TOOL", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
                Citizen.Wait(200)
                TriggerServerEvent('ls_wheel_theft:server:forceDeleteJackStand', extension.netId)
            end

            -- Then remove the jackstand bases with sound effects
            for i, jackInfo in ipairs(jackstands) do
                PlaySoundFrontend(-1, "REMOVE_TOOL", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
                Citizen.Wait(300)
                TriggerServerEvent('ls_wheel_theft:server:forceDeleteJackStand', jackInfo.netId)
            end

            Citizen.Wait(500)
            
            -- Clear animation and unfreeze player
            ClearPedTasks(playerPed)
            FreezeEntityPosition(playerPed, false)
            
            -- Unfreeze vehicle
            FreezeEntityPosition(veh, false)

            -- Update vehicle state
            TriggerServerEvent('ls_wheel_theft:server:setIsRaised', netId, false)
            
            -- Notify player
            QBCore.Functions.Notify('Vehicle lowered and jackstands retrieved.', 'success', 3000)
        else
            TriggerServerEvent('ls_wheel_theft:server:setIsRaised', netId, false)
            FreezeEntityPosition(veh, false)
        end

        return true
    end
    
    return false
end

-- Function to attach jack stands to vehicle at wheel positions
function AttachJackStandsToVehicle(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    
    -- Calculate positions for jackstands using vehicle dimensions
    local vehpos = GetEntityCoords(vehicle)
    local min, max = GetModelDimensions(GetEntityModel(vehicle))
    local width = ((max.x - min.x) / 2) - ((max.x - min.x) / 3.3)
    local length = ((max.y - min.y) / 2) - ((max.y - min.y) / 3.3)
    local zOffset = 0.5
    
    -- Get vehicle heading and convert to radians for precise positioning
    local vehHeading = GetEntityHeading(vehicle)
    local headingRad = math.rad(vehHeading)
    
    -- Request jackstand model
    local model = 'imp_prop_axel_stand_01a'
    RequestModel(model)
    
    -- Wait for model to load
    local modelTimeout = 10000
    while not HasModelLoaded(model) and modelTimeout > 0 do
        Citizen.Wait(100)
        modelTimeout = modelTimeout - 100
    end
    
    if not HasModelLoaded(model) then
        QBCore.Functions.Notify('Failed to load jackstand model', 'error', 5000)
        return false
    end
    
    -- Freeze vehicle to prevent movement during lifting
    FreezeEntityPosition(vehicle, true)
    
    -- Play sound when jackstand placement is started
    PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
    
    -- Calculate jackstand positions using heading for proper positioning
    -- Use trig functions to place jackstands relative to vehicle orientation
    local frontLeftOffset = vector3(-width, length, 0)
    local frontRightOffset = vector3(width, length, 0)
    local rearLeftOffset = vector3(-width, -length, 0)
    local rearRightOffset = vector3(width, -length, 0)
    
    -- Rotate the offsets based on vehicle heading
    local function rotateVector(vec, heading)
        local headingRad = math.rad(heading)
        local cosHeading = math.cos(headingRad)
        local sinHeading = math.sin(headingRad)
        return vector3(
            vec.x * cosHeading - vec.y * sinHeading,
            vec.x * sinHeading + vec.y * cosHeading,
            vec.z
        )
    end
    
    -- Rotate the offsets based on vehicle heading
    local flOffset = rotateVector(frontLeftOffset, vehHeading)
    local frOffset = rotateVector(frontRightOffset, vehHeading)
    local rlOffset = rotateVector(rearLeftOffset, vehHeading)
    local rrOffset = rotateVector(rearRightOffset, vehHeading)
    
    -- Calculate world positions for jackstands
    local flPosition = vector3(vehpos.x + flOffset.x, vehpos.y + flOffset.y, vehpos.z)
    local frPosition = vector3(vehpos.x + frOffset.x, vehpos.y + frOffset.y, vehpos.z)
    local rlPosition = vector3(vehpos.x + rlOffset.x, vehpos.y + rlOffset.y, vehpos.z)
    local rrPosition = vector3(vehpos.x + rrOffset.x, vehpos.y + rrOffset.y, vehpos.z)
    
    -- Get precise ground positions for each jackstand
    local _, flGroundZ = GetGroundZFor_3dCoord(flPosition.x, flPosition.y, flPosition.z, true)
    local _, frGroundZ = GetGroundZFor_3dCoord(frPosition.x, frPosition.y, frPosition.z, true)
    local _, rlGroundZ = GetGroundZFor_3dCoord(rlPosition.x, rlPosition.y, rlPosition.z, true)
    local _, rrGroundZ = GetGroundZFor_3dCoord(rrPosition.x, rrPosition.y, rrPosition.z, true)
    
    -- Create jackstands at ground level
    local flWheelStand = CreateObject(GetHashKey(model), flPosition.x, flPosition.y, flGroundZ, true, true, true)
    PlaceObjectOnGroundProperly(flWheelStand)
    Citizen.Wait(100)
    PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
    
    local frWheelStand = CreateObject(GetHashKey(model), frPosition.x, frPosition.y, frGroundZ, true, true, true)
    PlaceObjectOnGroundProperly(frWheelStand)
    Citizen.Wait(100)
    PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
    
    local rlWheelStand = CreateObject(GetHashKey(model), rlPosition.x, rlPosition.y, rlGroundZ, true, true, true)
    PlaceObjectOnGroundProperly(rlWheelStand)
    Citizen.Wait(100)
    PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
    
    local rrWheelStand = CreateObject(GetHashKey(model), rrPosition.x, rrPosition.y, rrGroundZ, true, true, true)
    PlaceObjectOnGroundProperly(rrWheelStand)
    PlaySoundFrontend(-1, "TOOL_BOX_ACTION_GENERIC", "GTAO_FM_VEHICLE_ARMORY_RADIO_SOUNDS", 0)
    
    -- Calculate rotation angles for jackstands
    -- Front jackstands should face inward toward the vehicle
    -- Rear jackstands should face outward from the vehicle
    local flRot = vector3(0.0, 0.0, vehHeading - 90.0)
    local frRot = vector3(0.0, 0.0, vehHeading - 90.0)
    local rlRot = vector3(0.0, 0.0, vehHeading + 90.0)
    local rrRot = vector3(0.0, 0.0, vehHeading + 90.0)
    
    -- Apply rotations to jackstands
    SetEntityRotation(flWheelStand, flRot.x, flRot.y, flRot.z, 2, true)
    SetEntityRotation(frWheelStand, frRot.x, frRot.y, frRot.z, 2, true)
    SetEntityRotation(rlWheelStand, rlRot.x, rlRot.y, rlRot.z, 2, true)
    SetEntityRotation(rrWheelStand, rrRot.x, rrRot.y, rrRot.z, 2, true)
    
    -- Get precise positions after placement
    local flStandPos = GetEntityCoords(flWheelStand)
    local frStandPos = GetEntityCoords(frWheelStand)
    local rlStandPos = GetEntityCoords(rlWheelStand)
    local rrStandPos = GetEntityCoords(rrWheelStand)
    
    -- Set collision properties
    SetEntityCollision(flWheelStand, false, true)
    SetEntityCollision(frWheelStand, false, true)
    SetEntityCollision(rlWheelStand, false, true)
    SetEntityCollision(rrWheelStand, false, true)
    
    -- Save jacks to entity state for later removal
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerServerEvent('ls_wheel_theft:server:saveJacks', netId, 
        NetworkGetNetworkIdFromEntity(flWheelStand), 
        NetworkGetNetworkIdFromEntity(frWheelStand), 
        NetworkGetNetworkIdFromEntity(rlWheelStand), 
        NetworkGetNetworkIdFromEntity(rrWheelStand), 
        true
    )
    
    -- Create thread for lifting the vehicle with simple approach
    Citizen.CreateThread(function()
        -- Get initial vehicle position
        local initialPos = GetEntityCoords(vehicle)
        if Config.debug then
            QBCore.Functions.Notify('Initial pos: ' .. vec2str(initialPos), 'primary', 3000)
        end
        
        -- Target lift height
        local liftHeight = 0.35 -- Increased for more visibility
        
        -- Request network control of vehicle
        NetworkRequestControlOfEntity(vehicle)
        local timeout = 2000
        while not NetworkHasControlOfEntity(vehicle) and timeout > 0 do
            Citizen.Wait(100)
            timeout = timeout - 100
        end
        
        -- Play hydraulic lift sound
        PlaySoundFrontend(-1, "VEHICLES_TRANSIT_HYDRAULIC_UP", "VEHICLES_TRANSIT_SOUND", 0)
        
        -- Unfreeze vehicle temporarily to allow lifting
        FreezeEntityPosition(vehicle, false)
        Citizen.Wait(100)
        
        -- Basic lift using coordinates (simplest and most reliable method)
        local newPos = vector3(initialPos.x, initialPos.y, initialPos.z + liftHeight)
        SetEntityCoords(vehicle, newPos.x, newPos.y, newPos.z, false, false, false, false)
        Citizen.Wait(100)
        
        -- Freeze vehicle in raised position
        FreezeEntityPosition(vehicle, true)
        
        -- Check if vehicle was actually raised
        local finalPos = GetEntityCoords(vehicle)
        local actualLift = finalPos.z - initialPos.z
        
        if Config.debug then
            QBCore.Functions.Notify('Final pos: ' .. vec2str(finalPos), 'primary', 3000)
            QBCore.Functions.Notify('Lift amount: ' .. tostring(actualLift), 'primary', 3000)
        end
        
        -- If lift was unsuccessful, try one more time with a different approach
        if actualLift < (liftHeight * 0.5) then
            if Config.debug then
                QBCore.Functions.Notify('First lift failed, trying backup method', 'error', 3000)
            end
            
            -- Alternative method with offset coordinates
            FreezeEntityPosition(vehicle, false)
            Citizen.Wait(100)
            SetEntityCoordsNoOffset(vehicle, initialPos.x, initialPos.y, initialPos.z + liftHeight, true, true, true)
            Citizen.Wait(100)
            FreezeEntityPosition(vehicle, true)
            
            -- Check again
            finalPos = GetEntityCoords(vehicle)
            actualLift = finalPos.z - initialPos.z
            
            if Config.debug then
                QBCore.Functions.Notify('Second attempt lift: ' .. tostring(actualLift), 'primary', 3000)
            end
        end
        
        -- Set decor to mark vehicle as raised
        DecorSetBool(vehicle, "WHEEL_THEFT_LIFTED", true)
        
        -- Play jackstand placement sound
        PlaySoundFrontend(-1, "JACK_VEHICLE", "HUD_MINI_GAME_SOUNDSET", 0)
        Citizen.Wait(200)
        PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", 0)
        
        -- Create extension objects for each jackstand (visual only)
        local extensionModel = 'prop_tool_jack'
        RequestModel(extensionModel)
        
        local modelTimeout = 5000
        while not HasModelLoaded(extensionModel) and modelTimeout > 0 do
            Citizen.Wait(100)
            modelTimeout = modelTimeout - 100
        end
        
        if HasModelLoaded(extensionModel) then
            local flExtension = CreateObject(GetHashKey(extensionModel), flStandPos.x, flStandPos.y, flStandPos.z, true, true, true)
            local frExtension = CreateObject(GetHashKey(extensionModel), frStandPos.x, frStandPos.y, frStandPos.z, true, true, true)
            local rlExtension = CreateObject(GetHashKey(extensionModel), rlStandPos.x, rlStandPos.y, rlStandPos.z, true, true, true)
            local rrExtension = CreateObject(GetHashKey(extensionModel), rrStandPos.x, rrStandPos.y, rrStandPos.z, true, true, true)
            
            -- Hide extensions (they're just for server tracking)
            SetEntityVisible(flExtension, false, false)
            SetEntityVisible(frExtension, false, false)
            SetEntityVisible(rlExtension, false, false)
            SetEntityVisible(rrExtension, false, false)
            
            -- Save extensions to entity state
            TriggerServerEvent('ls_wheel_theft:server:saveExtensionJacks', netId, 
                NetworkGetNetworkIdFromEntity(flExtension), 
                NetworkGetNetworkIdFromEntity(frExtension), 
                NetworkGetNetworkIdFromEntity(rlExtension), 
                NetworkGetNetworkIdFromEntity(rrExtension)
            )
        end
        
        -- Send success notification
        QBCore.Functions.Notify('Vehicle raised with jackstands', 'success', 3000)
    end)
    
    return true
end
