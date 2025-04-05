-- Global variable to track the work vehicle so we can despawn it later
WORK_VEHICLE = nil

function SpawnTruck()
    local truckTable = Config.spawnPickupTruck
    local vehicleModel = truckTable.models[math.random(1, #truckTable.models)]
    local availableSpotIndex = nil

    for k, spawnCoords in pairs(Config.spawnPickupTruck.truckSpawnCoords) do
        if not IsPlaceTaken(k) then
            availableSpotIndex = k
        end
    end

    if not availableSpotIndex then
        QBCore.Functions.Notify('No seats available at the moment', 'error', 5000)
        return
    end

    local vehicle = SpawnMissionVehicle(vehicleModel, truckTable.truckSpawnCoords[availableSpotIndex], true, true)
    -- Kanstori vehicle reference bach ndespawniha mn be3d fach mission t'cancella
    WORK_VEHICLE = vehicle
    TriggerEvent("vehiclekeys:client:SetOwner", GetVehicleNumberPlateText(vehicle))
end

function IsPlaceTaken(index)
    local truckTable = Config.spawnPickupTruck
    local coords = truckTable.truckSpawnCoords[index]

    local vehicle = GetNearestVehicle(coords.x, coords.y, coords.z, 1.0)

    if vehicle then
        return true
    else
        return false
    end
end

-- Function katdepawni mission fach t'cancella
function DespawnWorkVehicle()
    if WORK_VEHICLE and DoesEntityExist(WORK_VEHICLE) then
        QBCore.Functions.Notify('Removing work vehicle...', 'primary', 3000)
        
        -- Delete any wheels in the vehicle
        if STORED_WHEELS and #STORED_WHEELS > 0 then
            for i=1, #STORED_WHEELS do
                if DoesEntityExist(STORED_WHEELS[i]) then
                    DeleteEntity(STORED_WHEELS[i])
                end
            end
            STORED_WHEELS = {}
        end
        
        -- Mark as mission entity so it can be deleted
        SetEntityAsMissionEntity(WORK_VEHICLE, true, true)
        
        -- Delete the vehicle
        DeleteVehicle(WORK_VEHICLE)
        
        -- Reset the global variable
        WORK_VEHICLE = nil
        
        QBCore.Functions.Notify('Work vehicle removed!', 'success', 3000)
    end
    
    -- Ensure target vehicle is also cleaned up
    if TARGET_VEHICLE and DoesEntityExist(TARGET_VEHICLE) then
        QBCore.Functions.Notify('Removing target vehicle...', 'primary', 3000)
        
        -- Delete any brick props
        if MISSION_BRICKS and #MISSION_BRICKS > 0 then
            local brickCount = 0
            for k, brick in pairs(MISSION_BRICKS) do
                if DoesEntityExist(brick) then
                    DeleteEntity(brick)
                    brickCount = brickCount + 1
                end
            end
            QBCore.Functions.Notify('Removed ' .. brickCount .. ' brick props', 'success', 3000)
            MISSION_BRICKS = {}
        end
        
        -- Mark as mission entity so it can be deleted
        SetEntityAsMissionEntity(TARGET_VEHICLE, true, true)
        
        -- Delete the vehicle
        DeleteVehicle(TARGET_VEHICLE)
        
        -- Reset the global variable
        TARGET_VEHICLE = nil
        
        QBCore.Functions.Notify('Target vehicle removed!', 'success', 3000)
    end
end