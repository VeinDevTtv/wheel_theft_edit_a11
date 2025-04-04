local saleActive = false
local cooldown = false
local sellerBlip = false
HOLDING_WHEEL = nil
local storedWheels = {}
local sellerPedNetId = nil
local cratePropNetId = nil

function ContinueSale(sellerPed, crateProp)
    -- Store network IDs for ox_target
    sellerPedNetId = NetworkGetNetworkIdFromEntity(sellerPed)
    cratePropNetId = NetworkGetNetworkIdFromEntity(crateProp)
    
    -- Register the seller ped and crate with ox_target if enabled
    if Config.target.enabled then
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

-- Function to register the seller ped with ox_target
function RegisterSellerWithOxTarget(sellerPed)
    -- Define options for the seller ped
    local options = {
        {
            name = 'ls_wheel_theft:complete_sale',
            icon = 'fas fa-money-bill-wave',
            label = 'Complete Sale',
            canInteract = function()
                -- Only show if all 4 wheels are stored
                return #storedWheels == 4
            end,
            onSelect = function()
                if not cooldown then
                    SetCooldown(3000)
                    CompleteSale(sellerPed)
                end
            end
        }
    }
    
    -- Add the options to the entity using ox_target
    exports.ox_target:addEntity(sellerPedNetId, options)
end

-- Function to register the crate with ox_target
function RegisterCrateWithOxTarget(crateProp)
    -- Define options for the crate
    local options = {
        {
            name = 'ls_wheel_theft:drop_wheel',
            icon = 'fas fa-tire',
            label = 'Drop Off Wheel',
            canInteract = function()
                -- Only show if player is holding a wheel and not all wheels are stored
                return HOLDING_WHEEL and #storedWheels ~= 4
            end,
            onSelect = function()
                if not cooldown then
                    table.insert(storedWheels, HOLDING_WHEEL)
                    SetCooldown(3000)
                    DropOffWheel(crateProp, #storedWheels)
                end
            end
        }
    }
    
    -- Add the options to the entity using ox_target
    exports.ox_target:addEntity(cratePropNetId, options)
end

function CompleteSale(sellerPed)
    saleActive = false
    RetrieveMoney('sale_ped', sellerPed)

    SetEntityAsNoLongerNeeded(sellerPed)

    for k=1, #storedWheels, 1 do
        SetEntityAsNoLongerNeeded(storedWheels[k])
    end

    -- Clean up ox_target if it's enabled
    if Config.target.enabled then
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
    storedWheels = {}
    CancelMission()
end

function EnableSale()
    local sellerTable = Config.missionPeds['sale_ped']
    local ped = SpawnPed(sellerTable)
    local blip = sellerTable.blip
    local cratePropModel = sellerTable.wheelDropOff.crateProp
    local wheelDropOffCoords = sellerTable.wheelDropOff.location
    local crateProp = SpawnProp(cratePropModel, wheelDropOffCoords)

    FreezeEntityPosition(crateProp, true)

    if blip.showBlip then
        sellerBlip = CreateSellerBlip(GetEntityCoords(ped), blip.blipIcon, blip.blipColor, 1.0, 1.0, blip.blipLabel)

        if Config.enableBlipRoute then
            SetBlipRoute(sellerBlip, true)
        end
    end

    saleActive = true
    ContinueSale(ped, crateProp)
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
        -- Clean up the entities from ox_target when resource stops
        if sellerPedNetId then
            exports.ox_target:removeEntity(sellerPedNetId)
        end
        
        if cratePropNetId then
            exports.ox_target:removeEntity(cratePropNetId)
        end
    end
end)
