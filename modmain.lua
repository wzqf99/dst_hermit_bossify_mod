local STRINGS = GLOBAL.STRINGS
local SpawnPrefab = GLOBAL.SpawnPrefab

local TOKEN_PREFAB = "hermitcrab_boss_token"
local BOSS_PREFAB = "hermitcrab_boss"

PrefabFiles =
{
    TOKEN_PREFAB,
    BOSS_PREFAB,
}

STRINGS.NAMES.HERMITCRAB_BOSS_TOKEN = "帝王蟹的信物"
STRINGS.NAMES.HERMITCRAB_BOSS = "寄居蟹隐士"

for _, character_strings in pairs(STRINGS.CHARACTERS) do
    if type(character_strings) == "table" and type(character_strings.DESCRIBE) == "table" then
        character_strings.DESCRIBE.HERMITCRAB_BOSS_TOKEN = "瓶中的信物，似乎是写给寄居蟹隐士的。"
        character_strings.DESCRIBE.HERMITCRAB_BOSS = "她认真起来了。"
    end
end

local function CanStartEncounter(hermit, giver)
    local world = GLOBAL.TheWorld
    if world == nil or not world.ismastersim then
        return false
    end

    if hermit == nil or not hermit:IsValid() or hermit:IsInLimbo() then
        return false
    end

    if giver == nil or not giver:IsValid() or not giver:HasTag("player") then
        return false
    end

    if hermit.pearlgiven or hermit._hermitcrab_boss_starting then
        return false
    end

    if hermit._hermitcrab_boss ~= nil and hermit._hermitcrab_boss:IsValid() then
        return false
    end

    if world._hermitcrab_boss ~= nil and world._hermitcrab_boss:IsValid() then
        return false
    end

    if GLOBAL.TheSim:FindFirstEntityWithTag("hermitcrab_boss") ~= nil then
        return false
    end

    local relocation_manager = world.components.hermitcrab_relocation_manager
    if relocation_manager ~= nil and not relocation_manager:CanPearlMove() then
        return false
    end

    return true
end

local function StartEncounter(hermit, giver)
    if not CanStartEncounter(hermit, giver) then
        return false
    end

    hermit._hermitcrab_boss_starting = true

    local x, y, z = hermit.Transform:GetWorldPosition()
    hermit:RemoveFromScene()

    local boss = SpawnPrefab(BOSS_PREFAB)
    if boss == nil then
        hermit:ReturnToScene()
        hermit._hermitcrab_boss_starting = nil
        return false
    end

    boss.Transform:SetPosition(x, y, z)
    hermit._hermitcrab_boss = boss
    GLOBAL.TheWorld._hermitcrab_boss = boss
    hermit._hermitcrab_boss_starting = nil

    boss:SetEncounterHermit(hermit, giver)
    return true
end

AddPlayerPostInit(function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return
    end

    if inst.components.hermitbosstokenreceiver == nil then
        inst:AddComponent("hermitbosstokenreceiver")
    end
end)

AddPrefabPostInit("hermitcrab", function(inst)
    if not GLOBAL.TheWorld.ismastersim then
        return
    end

    local trader = inst.components.trader
    if trader == nil then
        return
    end

    local old_accept_test = trader.test
    local old_on_accept = trader.onaccept

    trader:SetAcceptTest(function(hermit, item, giver, count)
        if item ~= nil and item.prefab == TOKEN_PREFAB then
            return CanStartEncounter(hermit, giver)
        end

        return old_accept_test == nil or old_accept_test(hermit, item, giver, count)
    end)

    trader:SetOnAccept(function(hermit, giver, item, count)
        if item ~= nil and item.prefab == TOKEN_PREFAB then
            if StartEncounter(hermit, giver) then
                if item:IsValid() and giver ~= nil and giver.components.inventory ~= nil then
                    giver.components.inventory:GiveItem(item, nil, hermit:GetPosition())
                elseif item:IsValid() and hermit.components.inventory ~= nil then
                    hermit.components.inventory:DropItem(item, true, true)
                end
            elseif item:IsValid() then
                if giver ~= nil and giver.components.inventory ~= nil then
                    giver.components.inventory:GiveItem(item, nil, hermit:GetPosition())
                elseif hermit.components.inventory ~= nil then
                    hermit.components.inventory:DropItem(item, true, true)
                end
            end
            return
        end

        if old_on_accept ~= nil then
            old_on_accept(hermit, giver, item, count)
        end
    end)
end)
