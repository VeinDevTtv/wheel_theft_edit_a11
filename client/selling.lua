local saleActive = false
local cooldown = false
local sellerBlip = false
HOLDING_WHEEL = nil
local storedWheels = {}
local sellerPedNetId = nil
local cratePropNetId = nil

function ContinueSale(sellerPed, crateProp)
    -- Register the seller ped and crate with ox_target if enabled
    if Config.target.enabled then
        -- Wait a bit to ensure everything is properly loaded
        Citizen.Wait(2000)
        RegisterSellerWithOxTarget(sellerPed)
        RegisterCrateWithOxTarget(crateProp)
    end
    
    Citizen.CreateThread(function()
        local wheelTakeOutEnabled = false
        QBCore.Functions.Notify('Put the stolen wheels in the crate to finish the sale', 'inform', 7000)

        while saleActive do
            local sleep = 1000
            local player = PlayerPedId()
            local playerCoords = GetEntityCoords(player)
            local sellerCoords = GetEntityCoords(sellerPed)
            local crateCoords = GetEntityCoords(crateProp)

            -- Only use Draw3DText if ox_target is disabled
            if not Config.target.enabled then
                if HOLDING_WHEEL and #storedWheels ~= 4 then
                    if GetDistanceBetweenCoords(playerCoords.x, playerCoords.y, playerCoords.z, crateCoords.x, crateCoords.y, crateCoords.z, false) < 3.0 then
                        sleep = 1
                        Draw3DText(crateCoords.x, crateCoords.y, crateCoords.z, L('Press ~g~[~w~E~g~]~w~ to drop off wheel'), 4, 0.065, 0.065)

                        if IsControlJustReleased(0, Keys['E']) and not cooldown then
                            table.insert(storedWheels, HOLDING_WHEEL)
                            SetCooldown(3000)
                            DropOffWheel(crateProp, #storedWheels)
                        end
                    end

                elseif #storedWheels == 4 then
                    if GetDistanceBetweenCoords(playerCoords.x, playerCoords.y, playerCoords.z, sellerCoords.x, sellerCoords.y, sellerCoords.z, false) < 3.0 then
                        sleep = 1
                        Draw3DText(sellerCoords.x, sellerCoords.y, sellerCoords.z, L('Press ~g~[~w~E~g~]~w~ to complete the sale'), 4, 0.065, 0.065)

                        if IsControlJustReleased(0, Keys['E']) and not cooldown then
                            SetCooldown(3000)
                            CompleteSale(sellerPed)
                        end
                    end
                end
            end

            if not wheelTakeOutEnabled and GetDistanceBetweenCoords(playerCoords.x, playerCoords.y, playerCoords.z, crateCoords.x, crateCoords.y, crateCoords.z, false) < 50.0 then
                EnableWheelTakeOut()
                wheelTakeOutEnabled = true
            end

            Citizen.Wait(sleep)
        end
    end)
end

-- Add a command to directly register the seller with ox_target
RegisterCommand('debugSeller', function()
    local player = PlayerPedId()
    local playerCoords = GetEntityCoords(player)
    
    -- Find nearby peds
    local handle, ped = FindFirstPed()
    local success = true
    local peds = {}
    
    repeat
        if not IsPedAPlayer(ped) then
            local pedCoords = GetEntityCoords(ped)
            local distance = #(playerCoords - pedCoords)
            
            if distance < 10.0 then
                table.insert(peds, {ped = ped, distance = distance})
            end
        end
        
        success, ped = FindNextPed(handle)
    until not success
    
    EndFindPed(handle)
    
    -- Sort peds by distance
    table.sort(peds, function(a, b) return a.distance < b.distance end)
    
    if #peds > 0 then
        local closestPed = peds[1].ped
        QBCore.Functions.Notify('Found closest ped at distance: ' .. peds[1].distance, 'primary', 3000)
        
        -- Check if we can get a network ID
        local netId = NetworkGetNetworkIdFromEntity(closestPed)
        
        if netId == 0 then
            -- Try to make it networked
            NetworkRegisterEntityAsNetworked(closestPed)
            netId = NetworkGetNetworkIdFromEntity(closestPed)
            
            if netId == 0 then
                QBCore.Functions.Notify('Failed to get network ID for entity', 'error', 5000)
                return
            end
        end
        
        -- Create options for the ped
        local options = {
            {
                name = 'ls_wheel_theft:debug_complete_sale',
                icon = 'fas fa-dollar-sign',
                label = 'Complete Sale (Debug)',
                distance = 5.0,
                onSelect = function()
                    QBCore.Functions.Notify('Debug: Completing sale', 'primary', 3000)
                    CompleteSale(closestPed)
                end
            }
        }
        
        -- Add options to the entity
        exports.ox_target:addEntity(netId, options)
        QBCore.Functions.Notify('Added debug options to closest ped', 'success', 5000)
    else
        QBCore.Functions.Notify('No nearby peds found', 'error', 5000)
    end
end, false)

function EnableSale()
    local sellerTable = Config.missionPeds['sale_ped']
    if not sellerTable then
        QBCore.Functions.Notify('ERROR: Sale ped config missing', 'error', 5000)
        return
    end
    
    QBCore.Functions.Notify('Starting the sale process... Spawning seller and crate', 'inform', 4000)
    
    local ped = SpawnPed(sellerTable)
    local blip = sellerTable.blip
    local cratePropModel = sellerTable.wheelDropOff.crateProp
    local wheelDropOffCoords = sellerTable.wheelDropOff.location
    local crateProp = SpawnProp(cratePropModel, wheelDropOffCoords)

    if not DoesEntityExist(ped) then
        QBCore.Functions.Notify('ERROR: Failed to spawn seller ped', 'error', 5000)
        return
    end
    
    if not DoesEntityExist(crateProp) then
        QBCore.Functions.Notify('ERROR: Failed to spawn crate prop', 'error', 5000)
        return
    end

    -- Store references to clean up later
    sellerPedNetId = NetworkGetNetworkIdFromEntity(ped)
    cratePropNetId = NetworkGetNetworkIdFromEntity(crateProp)
    
    FreezeEntityPosition(crateProp, true)
    FreezeEntityPosition(ped, true)

    if blip.showBlip then
        sellerBlip = CreateSellerBlip(GetEntityCoords(ped), blip.blipIcon, blip.blipColor, 1.0, 1.0, blip.blipLabel)

        if Config.enableBlipRoute then
            SetBlipRoute(sellerBlip, true)
        end
    end

    saleActive = true
    ContinueSale(ped, crateProp)
    
    QBCore.Functions.Notify('Take your wheels to the crate and then complete the sale with the dealer', 'success', 8000)
end

-- Function to register the seller ped with ox_target
function RegisterSellerWithOxTarget(sellerPed)
    if not sellerPed or not DoesEntityExist(sellerPed) then
        QBCore.Functions.Notify('ERROR: Seller ped does not exist', 'error', 5000)
        return
    end
    
    local pedModel = GetEntityModel(sellerPed)
    local pedCoords = GetEntityCoords(sellerPed)
    
    QBCore.Functions.Notify('Registering seller for targeting...', 'primary', 2000)
    
    -- Clear any existing targets for this model to prevent duplicates
    exports.ox_target:removeModel(pedModel)
    
    -- Define options for the seller model
    local options = {
        {
            name = 'ls_wheel_theft:complete_sale',
            icon = 'fas fa-dollar-sign',
            label = 'Complete Sale',
            distance = 3.0,
            canInteract = function(entity)
                -- Only show if all 4 wheels are stored and this is the right ped
                -- Check position to ensure it's the right instance of this model
                local entityCoords = GetEntityCoords(entity)
                local distance = #(entityCoords - pedCoords)
                return distance < 1.0 and #storedWheels == 4
            end,
            onSelect = function()
                QBCore.Functions.Notify('Completing sale...', 'primary', 2000)
                CompleteSale(sellerPed)
            end
        }
    }
    
    -- Register with model targeting
    exports.ox_target:addModel(pedModel, options)
    QBCore.Functions.Notify('Seller registered for targeting! Speak to them when all wheels are dropped off.', 'success', 5000)
end

-- Function to register the crate with ox_target
function RegisterCrateWithOxTarget(crateProp)
    if not crateProp or not DoesEntityExist(crateProp) then
        QBCore.Functions.Notify('ERROR: Crate prop does not exist', 'error', 5000)
        return
    end
    
    local propModel = GetEntityModel(crateProp)
    local propCoords = GetEntityCoords(crateProp)
    
    QBCore.Functions.Notify('Registering crate for targeting...', 'primary', 2000)
    
    -- Clear any existing targets for this model to prevent duplicates
    exports.ox_target:removeModel(propModel)
    
    -- Define options for the crate
    local options = {
        {
            name = 'ls_wheel_theft:drop_wheel',
            icon = 'fas fa-car',
            label = 'Drop Off Wheel',
            distance = 3.0,
            canInteract = function(entity)
                -- Only show if player is holding a wheel and not all wheels are stored
                -- Check position to ensure it's the right instance of this model
                local entityCoords = GetEntityCoords(entity)
                local distance = #(entityCoords - propCoords)
                return distance < 1.0 and HOLDING_WHEEL ~= nil and #storedWheels < 4
            end,
            onSelect = function()
                QBCore.Functions.Notify('Dropping off wheel...', 'primary', 2000)
                table.insert(storedWheels, HOLDING_WHEEL)
                DropOffWheel(crateProp, #storedWheels)
            end
        }
    }
    
    -- Register with model targeting
    exports.ox_target:addModel(propModel, options)
    QBCore.Functions.Notify('Crate registered for targeting! Use target to drop off wheels.', 'success', 5000)
end

function CompleteSale(sellerPed)
    saleActive = false
    RetrieveMoney('sale_ped', sellerPed)

    -- Delete the seller ped
    if DoesEntityExist(sellerPed) then
        DeleteEntity(sellerPed)
    end

    -- Delete all stored wheels
    for k, wheel in pairs(storedWheels) do
        if wheel and DoesEntityExist(wheel) then
            DeleteEntity(wheel)
        end
    end
    storedWheels = {}
    
    -- Clean up ox_target if it's enabled
    if Config.target.enabled then
        -- Clean up model targeting
        local sellerModel = GetEntityModel(sellerPed)
        local crateModel = nil
        
        if Config.missionPeds and Config.missionPeds['sale_ped'] and Config.missionPeds['sale_ped'].wheelDropOff then
            crateModel = GetHashKey(Config.missionPeds['sale_ped'].wheelDropOff.crateProp)
            exports.ox_target:removeModel(crateModel)
        end
        
        exports.ox_target:removeModel(sellerModel)
        
        -- Also try to clean up entity targets if they exist
        if sellerPedNetId then
            exports.ox_target:removeEntity(sellerPedNetId)
        end
        
        if cratePropNetId then
            exports.ox_target:removeEntity(cratePropNetId)
        end
    end

    RemoveBlip(sellerBlip)
    sellerPedNetId = nil
    cratePropNetId = nil
    
    -- Set the paid state to prevent double payment
    LocalPlayer.state.AlreadyPaid = true
    
    -- Make server-side payment
    TriggerServerEvent('ls_wheel_theft:server:CompleteSale', #storedWheels)
    
    -- Mark mission as completed but pending final turn-in
    -- This will trigger the "Finish Mission" option at the mission giver
    Player(PlayerId()).state.MissionCompleted = true
    LocalPlayer.state.MissionCompleted = true
    QBCore.Functions.Notify('Sale completed! Return to the mission giver to finish the job.', 'success', 8000)
    
    -- Create a blip to guide the player back to the mission giver
    local missionTable = Config.missionPeds['mission_ped']
    local missionBlip = CreateSellerBlip(vector3(missionTable.location.x, missionTable.location.y, missionTable.location.z), 
        500, 2, 1.0, 1.0, "Return to Mission Giver")
    
    if Config.enableBlipRoute then
        SetBlipRoute(missionBlip, true)
    end
    
    -- Store the blip ID in both states to ensure it's accessible
    Player(PlayerId()).state.ReturnBlip = missionBlip
    LocalPlayer.state.ReturnBlip = missionBlip
    
    -- Keep the target vehicle - don't cancel the mission yet
    -- CancelMission() will be called when the player returns to the mission giver
end

function SetCooldown(time)
    cooldown = true
    Citizen.CreateThread(function()
        Citizen.Wait(time)
        cooldown = false
    end)
end

-- Event to remove the entities from ox_target when the resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName and Config.target.enabled then
        -- Clean up any model targets to prevent issues on resource restart
        -- These should be the models used by the seller and crate
        local sellerModel = GetHashKey(Config.missionPeds['sale_ped'].pedModel)
        local crateModel = GetHashKey(Config.missionPeds['sale_ped'].wheelDropOff.crateProp)
        
        exports.ox_target:removeModel(sellerModel)
        exports.ox_target:removeModel(crateModel)
        
        -- Also try to clean up entity-based targets if they exist
        if sellerPedNetId then
            exports.ox_target:removeEntity(sellerPedNetId)
        end
        
        if cratePropNetId then
            exports.ox_target:removeEntity(cratePropNetId)
        end
    end
end)

function DropOffWheel(crateProp, wheelCount)
    if not crateProp or not DoesEntityExist(crateProp) then
        QBCore.Functions.Notify('ERROR: Drop off crate does not exist', 'error', 5000)
        return
    end
    
    QBCore.Functions.Notify('Dropping off wheel ' .. wheelCount .. ' of 4...', 'primary', 3000)
    
    local player = PlayerPedId()
    local coords = GetEntityCoords(crateProp)

    -- Delete the wheel in player's hands
    if HOLDING_WHEEL and DoesEntityExist(HOLDING_WHEEL) then
        DeleteEntity(HOLDING_WHEEL)
        HOLDING_WHEEL = nil
        ClearPedTasksImmediately(player)
    end
    
    -- Create a new wheel in the crate (position depends on wheel count)
    local model = GetHashKey(Settings.wheelTakeOff.wheelModel)
    
    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            Citizen.Wait(1)
        end
    end
    
    -- Adjust position based on which wheel number this is
    local xOffset = 0.0
    local yOffset = 0.0
    
    if wheelCount == 1 then 
        xOffset = -0.3
        yOffset = 0.3
    elseif wheelCount == 2 then
        xOffset = 0.3
        yOffset = 0.3
    elseif wheelCount == 3 then
        xOffset = -0.3
        yOffset = -0.3
    elseif wheelCount == 4 then
        xOffset = 0.3
        yOffset = -0.3
    end
    
    local wheelProp = CreateObject(model, coords.x + xOffset, coords.y + yOffset, coords.z, true, true, true)
    
    -- Register as networked object
    NetworkRegisterEntityAsNetworked(wheelProp)
    local netId = NetworkGetNetworkIdFromEntity(wheelProp)
    SetNetworkIdCanMigrate(netId, true)
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetEntityAsMissionEntity(wheelProp, true, true)
    
    FreezeEntityPosition(wheelProp, true)
    
    -- Store the wheel properly in the storedWheels array at the specific index
    storedWheels[wheelCount] = wheelProp
    
    if wheelCount == 4 then
        QBCore.Functions.Notify('All wheels have been dropped off. Speak to the seller to complete the sale!', 'success', 5000)
    end
end
