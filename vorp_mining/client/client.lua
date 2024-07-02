local MinePrompt
local active = false
local sleep = true
local tool, hastool, UsePrompt, PropPrompt
local swing = 0
local MinedRocks = {}
local nearby_rocks

local rockGroup = GetRandomIntInRange(0, 0xffffff)

T = Translation.Langs[Lang]

function CreateStartMinePrompt()
    Citizen.CreateThread(function()
        local str = T.PromptLabels.mineLabel
        MinePrompt = Citizen.InvokeNative(0x04F97DE45A519419)
        PromptSetControlAction(MinePrompt, Config.MinePromptKey)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(MinePrompt, str)
        PromptSetEnabled(MinePrompt, true)
        PromptSetVisible(MinePrompt, true)
        PromptSetHoldMode(MinePrompt, true)
        PromptSetGroup(MinePrompt, rockGroup)
        PromptRegisterEnd(MinePrompt)
    end)
end

function GetRockNearby(coords, radius, hash_filter)
    local itemSet = CreateItemset(true)
    local size = Citizen.InvokeNative(0x59B57C4B06531E1E, coords, radius, itemSet, 3, Citizen.ResultAsInteger())
    local found_entity

    if size > 0 then
        for index = 0, size - 1 do
            local entity = GetIndexedItemInItemset(index, itemSet)
            local model_hash = GetEntityModel(entity)

            if hash_filter[model_hash] then
                local rock_coords = GetEntityCoords(entity)
                local rock_x, rock_y, rock_z = table.unpack(rock_coords)

                found_entity = {
                    model_name = hash_filter[model_hash],
                    entity = entity,
                    model_hash = model_hash,
                    vector_coords = rock_coords,
                    x = rock_x,
                    y = rock_y,
                    z = rock_z,
                }

                break
            end
        end
    end

    if IsItemsetValid(itemSet) then
        DestroyItemset(itemSet)
    end

    return found_entity
end

function isPlayerReadyToMineRocks(player)
    if IsPedOnMount(player) then
        return false
    end

    if IsPedInAnyVehicle(player) then
        return false
    end

    if IsPedDeadOrDying(player) then
        return false
    end

    if IsEntityInWater(player) then
        return false
    end

    if IsPedClimbing(player) then
        return false
    end

    if not IsPedOnFoot(player) then
        return false
    end

    return true
end

function coordsToString(coords)
    return round(coords[1], 1) .. '-' .. round(coords[2], 1) .. '-' .. round(coords[3], 1)
end

function isRockAlreadyMined(coords)
    local coords_string = coordsToString(coords)
    local result = MinedRocks[coords_string] == true
    return result
end

function rememberRockAsMined(coords)
    local coords_string = coordsToString(coords)
    MinedRocks[coords_string] = true
end

function forgetRockAsMined(coords)
    local coords_string = coordsToString(coords)
    MinedRocks[coords_string] = nil
end

function isInRestrictedTown(restricted_towns, player_coords)
    player_coords = player_coords or GetEntityCoords(PlayerPedId())

    local x, y, z = table.unpack(player_coords)
    local town_hash = GetTown(x, y, z)

    if town_hash == false then
        return false
    end

    if restricted_towns[town_hash] then
        return true
    end

    return false
end

function getUnMinedNearbyRock(allowed_model_hashes, player, player_coords)
    player = player or PlayerPedId()

    if not isPlayerReadyToMineRocks(player) then
        return nil
    end

    player_coords = player_coords or GetEntityCoords(player)

    local found_nearby_rocks = GetRockNearby(player_coords, 1.6, allowed_model_hashes)

    if not found_nearby_rocks then
        return nil
    end

    if isRockAlreadyMined(found_nearby_rocks.vector_coords) then
        return nil
    end

    return found_nearby_rocks
end

function showStartMineBtn()
    local MiningGroupName = CreateVarString(10, 'LITERAL_STRING', T.PromptLabels.mineDesc)
    PromptSetActiveGroupThisFrame(rockGroup, MiningGroupName)
end

function checkStartMineBtnPressed(rock)
    if PromptHasHoldModeCompleted(MinePrompt) then
        active = true
        local player = PlayerPedId()
        SetCurrentPedWeapon(player, GetHashKey("WEAPON_UNARMED"), true, 0, false, false)
        Citizen.Wait(500)
        TriggerServerEvent("vorp_mining:pickaxecheck", rock.vector_coords)
    end
end

function convertConfigRocksToHashRegister()
    local model_hashes = {}

    for _, model_name in pairs(Config.Rocks) do
        local model_hash = GetHashKey(model_name)
        model_hashes[model_hash] = model_name
    end

    return model_hashes
end

function doNothingAndWait()
    Citizen.Wait(500)
end

function waitForStartKey(rock)
    showStartMineBtn()

    checkStartMineBtnPressed(rock)

    Citizen.Wait(0)
end

function GetTown(x, y, z)
    return Citizen.InvokeNative(0x43AD8FC02B429D33, x, y, z, 1)
end

function convertConfigTownRestrictionsToHashRegister()
    local restricted_towns = {}

    for _, town_restriction in pairs(Config.TownRestrictions) do
        if not town_restriction.mine_allowed then
            local town_hash = GetHashKey(town_restriction.name)
            restricted_towns[town_hash] = town_restriction.name
        end
    end

    return restricted_towns
end

function manageStartMinePrompt(restricted_towns, player_coords)
    local is_promp_enabled = true

    if isInRestrictedTown(restricted_towns, player_coords) then
        is_promp_enabled = false
    end
    PromptSetEnabled(MinePrompt, is_promp_enabled)
end

Citizen.CreateThread(function()
    local allowed_rock_model_hashes = convertConfigRocksToHashRegister()

    local restricted_towns = convertConfigTownRestrictionsToHashRegister()

    while true do
        if active == false then
            local player = PlayerPedId()
            local player_coords = GetEntityCoords(player)

            nearby_rocks = getUnMinedNearbyRock(allowed_rock_model_hashes, player, player_coords)

            if nearby_rocks and not isRockAlreadyMined(nearby_rocks.vector_coords) then
                manageStartMinePrompt(restricted_towns, player_coords)
            end
        end

        doNothingAndWait()
    end
end)

Citizen.CreateThread(function()
    CreateStartMinePrompt()

    while true do
        if isUsingPickaxe then
            if active == false and nearby_rocks then
                waitForStartKey(nearby_rocks)
            else
                doNothingAndWait()
            end
        else
            -- Se a picareta não estiver sendo usada, você pode adicionar uma lógica aqui
            -- Por exemplo, exibir uma mensagem ou simplesmente esperar
            Citizen.Wait(1000)  -- Espera por um segundo antes de verificar novamente
        end
    end
end)


RegisterNetEvent("vorp_mining:pickaxechecked")
AddEventHandler("vorp_mining:pickaxechecked", function(rock)
    goMine(rock)
end)

RegisterNetEvent("vorp_mining:nopickaxe")
AddEventHandler("vorp_mining:nopickaxe", function()
    active = false
end)

function releasePlayer()
    if PropPrompt then
        PromptSetEnabled(PropPrompt, false)
        PromptSetVisible(PropPrompt, false)
    end

    if UsePrompt then
        PromptSetEnabled(UsePrompt, false)
        PromptSetVisible(UsePrompt, false)
    end

    FreezeEntityPosition(PlayerPedId(), false)
end

function removeMiningPrompt()
    if MinePrompt then
        PromptSetEnabled(MinePrompt, false)
        PromptSetVisible(MinePrompt, false)
    end
end

function rockFinished(rock)
    swing = 0

    rememberRockAsMined(rock)
    Wait(2300)
    DefreezePlayer()

    active = false

    Citizen.CreateThread(function()
        Citizen.Wait(1800000)
        forgetRockAsMined(rock)
    end)
end

function DefreezePlayer()
    hastool = false

    if not tool then
        return
    end

    tool = nil
end

function goMine(rock)
    AnimationMine('Swing')
    local swingcount = math.random(Config.MinSwing, Config.MaxSwing)
    while hastool == true do
        FreezeEntityPosition(PlayerPedId(), true)
        if IsControlJustReleased(0, Config.StopMiningKey) or IsPedDeadOrDying(PlayerPedId()) then
            rockFinished(rock)
        elseif IsControlJustPressed(0, Config.MineRockKey) then
            PromptSetEnabled(UsePrompt, false)
            local randomizer = math.random(Config.maxDifficulty, Config.minDifficulty)
            swing = swing + 1
            Anim(ped, 'amb_work@world_human_pickaxe_new@working@male_a@trans', 'pre_swing_trans_after_swing', -1, 0)
            local testplayer = exports["syn_minigame"]:taskBar(randomizer, 7)
            if testplayer == 100 then
                TriggerServerEvent('vorp_mining:addItem')
            else
                local minning_fail_txt_index = math.random(1, #T)
                local minning_fail_txt = T[minning_fail_txt_index]
                TriggerEvent("vorp:TipRight", minning_fail_txt, 3000)
            end
            Wait(500)
            PromptSetEnabled(UsePrompt, true)
        end

        if swing == swingcount then
            PromptSetEnabled(UsePrompt, false)
            rockFinished(rock)
        end
        Wait(5)
    end
    releasePlayer()
    active = false
end

function AnimationMine(prompttext, holdtowork)
    hastool = false
    Citizen.InvokeNative(0x6A2F820452017EA2) -- Clear Prompts from Screen
    if tool then
    DeleteEntity(tool)
    end
    Wait(500)
    FPrompt()
    LMPrompt(prompttext, Config.MineRockKey, holdtowork)
    ped = PlayerPedId()
    ForceEntityAiAndAnimationUpdate(tool, 1)

    Wait(500)
    PromptSetEnabled(PropPrompt, true)
    PromptSetVisible(PropPrompt, true)
    PromptSetEnabled(UsePrompt, true)
    PromptSetVisible(UsePrompt, true)

    hastool = true
end

function FPrompt(text, button, hold)
    Citizen.CreateThread(function()
        proppromptdisplayed = false
        PropPrompt = nil
        local str = T.PromptLabels.keepPickaxe
        local buttonhash = button or Config.StopMiningKey
        local holdbutton = hold or false
        PropPrompt = PromptRegisterBegin()
        PromptSetControlAction(PropPrompt, buttonhash)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(PropPrompt, str)
        PromptSetEnabled(PropPrompt, false)
        PromptSetVisible(PropPrompt, false)
        PromptSetHoldMode(PropPrompt, holdbutton)
        PromptRegisterEnd(PropPrompt)
        sleep = true
    end)
end

function LMPrompt(text, button, hold)
    Citizen.CreateThread(function()
        UsePrompt = nil
        local str = T.PromptLabels.usePickaxe
        local buttonhash = button or Config.MineRockKey
        local holdbutton = hold or false
        UsePrompt = PromptRegisterBegin()
        PromptSetControlAction(UsePrompt, buttonhash)
        str = CreateVarString(10, 'LITERAL_STRING', str)
        PromptSetText(UsePrompt, str)
        PromptSetEnabled(UsePrompt, false)
        PromptSetVisible(UsePrompt, false)
        if hold then
            PromptSetHoldIndefinitelyMode(UsePrompt)
        end
        PromptRegisterEnd(UsePrompt)
    end)
end

function Anim(actor, dict, body, duration, flags, introtiming, exittiming)
    Citizen.CreateThread(function()
        RequestAnimDict(dict)
        local dur = duration or -1
        local flag = flags or 1
        local intro = tonumber(introtiming) or 1.0
        local exit = tonumber(exittiming) or 1.0
        timeout = 5
        while (not HasAnimDictLoaded(dict) and timeout > 0) do
            timeout = timeout - 1
            if timeout == 0 then
                print("Animation Failed to Load")
            end
            Citizen.Wait(300)
        end
        TaskPlayAnim(actor, dict, body, intro, exit, dur, flag --[[1 for repeat--]], 1, false, false, false, 0, true)
    end)
end

function GetArrayKey(array, value)
    for k, v in pairs(array) do
        if v == value then
            return k
        end
    end
    return false
end

function InArray(array, item)
    for k, v in pairs(array) do
        if v == item then
            return true
        end
    end
    return false
end

function round(num, decimals)
    if type(num) ~= "number" then
        return num
    end

    local multiplier = 10 ^ (decimals or 0)
    return math.floor(num * multiplier + 0.5) / multiplier
end

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    DefreezePlayer()
    releasePlayer()
    removeMiningPrompt()
end)

RegisterNetEvent("vorp_inventory:client:UsePickaxe")
AddEventHandler("vorp_inventory:client:UsePickaxe", function()
    local ped = PlayerPedId()

    if isUsingPickaxe then
        -- Se a picareta já está sendo usada, remova-a
        DeleteObject(pickaxe)
        pickaxe = nil
        isUsingPickaxe = false

        -- Exibir uma dica usando o VorpCore à direita
        TriggerEvent("vorp:TipRight", "Você parou de usar a picareta.")

        -- Chama a função nativa quando o jogador deixa de usar a picareta
        Citizen.InvokeNative(0x58F7DB5BD8FA2288, PlayerPedId())

        return
    end

local armasEquipadas, weaponHash = verificarArmasEquipadas()

if armasEquipadas then
    print("Arma equipada: " .. weaponHash)

    -- Limpa as tarefas do jogador
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
    Citizen.InvokeNative(0xFCCC886EDE3C63EC, ped, 2, 0) -- Removes Weapon from animation

    Citizen.Wait(1500)
else
    print("O jogador está desarmado (Unarmed).")
end

    -- Cria a picareta e a anexa ao jogador
    local boneIndex = GetPedBoneIndex(ped, 57005)  -- 57005 é o código do bone que funciona corretamente
    pickaxe = CreateObject(GetHashKey("p_pickaxe01x"), GetEntityCoords(ped), true, true, true)
    AttachEntityToEntity(pickaxe, ped, GetPedBoneIndex(ped, 7966), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0, 0, 0, 2, 1, 0, 0)
    Citizen.InvokeNative(0x923583741DC87BCE, ped, 'arthur_healthy')
    Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, "carry_pitchfork")
    Citizen.InvokeNative(0x2208438012482A1A, ped, true, true)
    ForceEntityAiAndAnimationUpdate(pickaxe, 1)
    Citizen.InvokeNative(0x3A50753042B6891B, ped, "PITCH_FORKS")

    -- Exibir uma dica usando o VorpCore à direita
    TriggerEvent("vorp:TipRight", "Você está usando a picareta.")

    isUsingPickaxe = true  -- Marca que a picareta está sendo usada
end)

local blockedKeys = {
    0x07CE1E61,  -- Botão esquerdo do mouse
    0xF84FA74F,  -- Botão direito do mouse
    0xB2F377E8,  -- Tecla F
    0xAC4BD4F1,  -- Tecla Tab (para sacar arma)
    0xB238FE0B   -- Tecla Tab (para sacar arma)
}

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if isUsingPickaxe then
            -- Bloquear as teclas especificadas
            for _, key in ipairs(blockedKeys) do
                DisableControlAction(0, key, true)
            end
        else
            -- Liberar as teclas quando não estiver usando a picareta
            for _, key in ipairs(blockedKeys) do
                EnableControlAction(0, key, true)
            end
        end
    end
end)

function verificarArmasEquipadas()
    local ped = PlayerPedId()
    local attachPoint = 0

    local retval, weaponHash = GetCurrentPedWeapon(ped, false, attachPoint, false)

    if retval then
        if weaponHash ~= -1569615261 then -- Check if not unarmed
            return true, weaponHash
        else
            return false, weaponHash
        end
    else
        print("Não foi possível obter a arma atual.")
        return false, 0
    end
end

Citizen.CreateThread(function()
    retval = true -- Initialize isUsingPickaxe as true to start the loop

    while retval do
        Citizen.Wait(1) -- Dont change to 0 or remove crash Game!!!

        if isUsingPickaxe then
            local ped = PlayerPedId()
            Citizen.InvokeNative(0xFCCC886EDE3C63EC, ped, 2, 1) -- Remove weapon animation
        end
    end
end)







