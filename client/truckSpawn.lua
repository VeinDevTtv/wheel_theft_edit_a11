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
        -- Set as mission entity to ensure proper cleanup
        SetEntityAsMissionEntity(WORK_VEHICLE, true, true)
        DeleteVehicle(WORK_VEHICLE)
        WORK_VEHICLE = nil
        QBCore.Functions.Notify('Work vehicle has been returned', 'inform', 5000)
    end
end