function SpawnPed(pedTable)
    local coord = pedTable.location
    local model = GetHashKey(pedTable.pedModel)
    
    if not HasModelLoaded(model) then
        RequestModel(model)
        
        local timeout = 10000
        while not HasModelLoaded(model) and timeout > 0 do
            timeout = timeout - 100
            Citizen.Wait(100)
        end
        
        if timeout <= 0 then
            QBCore.Functions.Notify('Failed to load ped model', 'error', 5000)
            return nil
        end
    end
    
    -- Create the ped as a networked entity so it can be tracked
    local ped = CreatePed(4, model, coord.x, coord.y, coord.z - 1.0, coord.h, true, true)
    
    -- Ensure the ped is registered with the network system
    NetworkRegisterEntityAsNetworked(ped)
    local netId = NetworkGetNetworkIdFromEntity(ped)
    SetNetworkIdCanMigrate(netId, true)
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedAsNoLongerNeeded(ped)
    
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    SetPedCanBeTargetted(ped, true)
    
    QBCore.Functions.Notify('Spawned ped with net ID: ' .. netId, 'primary', 3000)
    
    return ped
end

function SpawnProp(modelName, location)
    local model = GetHashKey(modelName)
    
    if not HasModelLoaded(model) then
        RequestModel(model)
        
        local timeout = 10000
        while not HasModelLoaded(model) and timeout > 0 do
            timeout = timeout - 100
            Citizen.Wait(100)
        end
        
        if timeout <= 0 then
            QBCore.Functions.Notify('Failed to load prop model', 'error', 5000)
            return nil
        end
    end
    
    -- Create prop as a networked entity
    local prop = CreateObject(model, location.x, location.y, location.z - 1.0, true, true, true)
    
    -- Ensure the prop is registered with the network system
    NetworkRegisterEntityAsNetworked(prop)
    local netId = NetworkGetNetworkIdFromEntity(prop)
    SetNetworkIdCanMigrate(netId, true)
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetEntityAsMissionEntity(prop, true, true)
    SetEntityHeading(prop, location.h or 0.0)
    
    QBCore.Functions.Notify('Spawned prop with net ID: ' .. netId, 'primary', 3000)
    
    return prop
end 