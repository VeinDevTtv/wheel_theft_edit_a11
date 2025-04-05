TARGET_VEHICLE = nil
CLOSEST_VEHICLE = nil

RegisterServerEvent('ls_wheel_theft:Sell')
AddEventHandler('ls_wheel_theft:Sell', function(sellingKey)
    local _source = source
    local selling = Config.missionPeds[sellingKey]

    AddMoney(_source, selling.price)
end)

RegisterServerEvent('ls_wheel_theft:server:setIsRaised')
AddEventHandler('ls_wheel_theft:server:setIsRaised', function(netId, raised)
    local veh = NetworkGetEntityFromNetworkId(netId)

    if not DoesEntityExist(veh) then
        return
    end

    Entity(veh).state.IsVehicleRaised = raised
end)

RegisterServerEvent('ls_wheel_theft:PoliceAlert')
AddEventHandler('ls_wheel_theft:PoliceAlert', function(locationCoords)
    local _source = source
    locationCoords = json.decode(locationCoords)

    if Config.dispatch.enabled then
        if Config.dispatch.system == 'in-built' then
            for _, playerId in ipairs(GetPlayers()) do
                playerId = tonumber(playerId)
                if IsPolice(playerId) then
                    TriggerClientEvent('ls_wheel_theft:activatePoliceAlarm', playerId, locationCoords)
                end
            end
        else
            TriggerClientEvent('ls_wheel_theft:TriggerDispatchMessage', _source, locationCoords)
        end
    end
end)

RegisterServerEvent('ls_wheel_theft:RetrieveItem')
AddEventHandler('ls_wheel_theft:RetrieveItem', function(itemName)
    local _source = source
    RetrieveItem(_source, itemName)
end)

RegisterNetEvent('ls_wheel_theft:server:removeItem')
AddEventHandler('ls_wheel_theft:server:removeItem', function(item, amount)
    local _source = source
    RemovePlayerItem(_source, item, amount)
end)

RegisterServerEvent('ls_wheel_theft:ResetPlayerState')
AddEventHandler('ls_wheel_theft:ResetPlayerState', function(netId)
    local _source = source
    Wait(5000)
    Player(_source).state.WheelTheftMission = false
end)

RegisterServerEvent('ls_wheel_theft:server:forceDeleteJackStand')
AddEventHandler('ls_wheel_theft:server:forceDeleteJackStand', function(state)
    local entity = NetworkGetEntityFromNetworkId(state)
    DeleteEntity(entity)
end)

RegisterServerEvent('ls_wheel_theft:server:saveJacks')
AddEventHandler('ls_wheel_theft:server:saveJacks', function(netId, jack1, jack2, jack3, jack4)
    local veh = NetworkGetEntityFromNetworkId(netId)

    if not DoesEntityExist(veh) then
        return
    end

    Entity(veh).state.jackStand1 = jack1
    Entity(veh).state.jackStand2 = jack2
    Entity(veh).state.jackStand3 = jack3
    Entity(veh).state.jackStand4 = jack4
end)

function Contains(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end


exports('ls_jackstand', function(event, item, inventory, slot, data)
    if event == 'usingItem' then
        local itemSlot = exports.ox_inventory:GetSlot(inventory.id, slot)
        if itemSlot ~= nil then
            TriggerClientEvent('ls_wheel_theft:LiftVehicle', inventory.id)
            --exports.ox_inventory:RemoveItem(inventory.id, item, 1, nil, slot)
        end
    end
end)

-- Event handler for completion bonus when player returns to mission giver
RegisterServerEvent('ls_wheel_theft:server:GiveJobBonus')
AddEventHandler('ls_wheel_theft:server:GiveJobBonus', function()
    local _source = source
    -- Define the bonus reward amount 
    local bonusAmount = math.random(300, 500) -- Adjust the bonus range as needed
    
    -- Add the bonus reward
    AddMoney(_source, bonusAmount)
    
    -- Notify the player
    TriggerClientEvent('QBCore:Notify', _source, 'You received a bonus of $'..bonusAmount..' for completing the job!', 'success', 5000)
end)

-- Event handler for completing the sale at the seller
RegisterServerEvent('ls_wheel_theft:server:CompleteSale')
AddEventHandler('ls_wheel_theft:server:CompleteSale', function(wheelCount)
    local _source = source
    -- Calculate payment based on number of wheels
    local payPerWheel = 250 -- Base amount per wheel
    local totalPay = wheelCount * payPerWheel
    
    -- Add a random bonus to make the payment more interesting
    local randomBonus = math.random(100, 300)
    totalPay = totalPay + randomBonus
    
    -- Add the money to the player
    AddMoney(_source, totalPay)
    
    -- Notify the player
    TriggerClientEvent('QBCore:Notify', _source, 'You received $'..totalPay..' for selling '..wheelCount..' wheels!', 'success', 5000)
end)

-- Event handler to refresh mission ped targeting options
RegisterServerEvent('ls_wheel_theft:server:refreshMissionPed')
AddEventHandler('ls_wheel_theft:server:refreshMissionPed', function()
    local _source = source
    
    -- Broadcast to all clients to refresh mission ped (including the source client)
    TriggerClientEvent('ls_wheel_theft:client:refreshMissionPed', -1, _source)
end)