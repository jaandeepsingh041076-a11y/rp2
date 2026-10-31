-- ─────────────────────────────────────────────────────────────
--  grand_items: client/main.lua
--  Consumable Usage Animations & Sound Effects
-- ─────────────────────────────────────────────────────────────

RegisterNetEvent('grand_items:useFood', function(itemName, hungerAmount, thirstAmount)
    local ped = PlayerPedId()

    -- Burger eating animation
    RequestAnimDict("mp_player_inteat@burger")
    while not HasAnimDictLoaded("mp_player_inteat@burger") do Wait(10) end

    local model = GetHashKey("prop_cs_burger_01")
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local pCoords = GetEntityCoords(ped)
    local prop = CreateObject(model, pCoords.x, pCoords.y, pCoords.z, true, true, true)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 18905), 0.13, 0.05, 0.02, -50.0, 16.0, 60.0, true, true, false, true, 1, true)

    TaskPlayAnim(ped, "mp_player_inteat@burger", "mp_player_int_eat_burger", 2.0, 2.0, 4500, 49, 0, false, false, false)
    Wait(4500)

    DeleteObject(prop)
    TriggerServerEvent('grand_items:applyVitals', hungerAmount, thirstAmount)
    TriggerEvent('grand_notify:Alert', 'Grand Consumable', 'Finished eating delicious meal!', 'success', 3000)
end)

RegisterNetEvent('grand_items:useDrink', function(itemName, thirstAmount)
    local ped = PlayerPedId()

    RequestAnimDict("mp_player_intdrink")
    while not HasAnimDictLoaded("mp_player_intdrink") do Wait(10) end

    local model = GetHashKey("prop_ld_can_01")
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(10) end

    local pCoords = GetEntityCoords(ped)
    local prop = CreateObject(model, pCoords.x, pCoords.y, pCoords.z, true, true, true)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)

    TaskPlayAnim(ped, "mp_player_intdrink", "loop_bottle", 2.0, 2.0, 3500, 49, 0, false, false, false)
    Wait(3500)

    DeleteObject(prop)
    TriggerServerEvent('grand_items:applyVitals', 0, thirstAmount)
    TriggerEvent('grand_notify:Alert', 'Grand Consumable', 'Feeling refreshed and hydrated!', 'success', 3000)
end)
