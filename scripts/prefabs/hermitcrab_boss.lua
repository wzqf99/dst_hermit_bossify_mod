local brain = require("brains/hermitcrab_bossbrain")

local assets =
{
    Asset("ANIM", "anim/player_basic.zip"),
    Asset("ANIM", "anim/player_actions.zip"),
    Asset("ANIM", "anim/player_actions_item.zip"),
    Asset("ANIM", "anim/player_hermitcrab_idle.zip"),
    Asset("ANIM", "anim/player_hermitcrab_walk.zip"),
    Asset("ANIM", "anim/player_hermitcrab_look.zip"),
    Asset("ANIM", "anim/hermitcrab_build.zip"),
    Asset("SOUND", "sound/sfx.fsb"),
    Asset("SOUND", "sound/wilson.fsb"),
}

local prefabs =
{
    "hermit_pearl",
}

local MAX_HEALTH = 1500
local DAMAGE = 40
local ATTACK_PERIOD = 2
local TARGET_DISTANCE = 20
local KEEP_TARGET_DISTANCE = 30
local ENCOUNTER_DISTANCE = 35
local EMPTY_ENCOUNTER_TIMEOUT = 10
local WATCH_PERIOD = 2

local TARGET_MUST_TAGS = { "player" }
local TARGET_CANT_TAGS = { "playerghost", "INLIMBO" }

local function Retarget(inst)
    return FindEntity(inst, TARGET_DISTANCE, function(target)
        return inst.components.combat:CanTarget(target)
    end, TARGET_MUST_TAGS, TARGET_CANT_TAGS)
end

local function KeepTarget(inst, target)
    return target ~= nil
        and target:IsValid()
        and not target:HasTag("playerghost")
        and inst:IsNear(target, KEEP_TARGET_DISTANCE)
        and inst.components.combat:CanTarget(target)
end

local function HasNearbyLivingPlayer(inst)
    for _, player in ipairs(AllPlayers) do
        if player:IsValid()
            and not player:HasTag("playerghost")
            and not player:IsInLimbo()
            and inst:IsNear(player, ENCOUNTER_DISTANCE) then
            return true
        end
    end

    return false
end

local function WatchEncounter(inst)
    if inst._encounter_resolved or inst._surrendering then
        return
    end

    if HasNearbyLivingPlayer(inst) then
        inst._empty_encounter_time = 0
    else
        inst._empty_encounter_time = inst._empty_encounter_time + WATCH_PERIOD
        if inst._empty_encounter_time >= EMPTY_ENCOUNTER_TIMEOUT then
            inst:FinishEncounter(false)
        end
    end
end

local function BeginSurrender(inst)
    if inst._surrendering or inst._encounter_resolved then
        return
    end

    inst._surrendering = true
    inst.components.health:SetInvincible(true)
    inst.components.combat:SetTarget(nil)
    inst.components.combat:CancelAttack()
    inst:PushEvent("hermitboss_surrender")
end

local function OnHealthDelta(inst)
    if inst.components.health.currenthealth <= inst.components.health.minhealth then
        BeginSurrender(inst)
    end
end

local function LearnPearlReward(hermit)
    if hermit.components.craftingstation ~= nil
        and not hermit.components.craftingstation:KnowsItem("winter_ornament_boss_pearl") then
        hermit.components.craftingstation:LearnItem(
            "winter_ornament_boss_pearl",
            "hermitshop_winter_ornament_boss_pearl"
        )
    end
end

local function FinishEncounter(inst, victory, already_removing)
    if inst._encounter_resolved then
        return
    end

    inst._encounter_resolved = true

    if inst._watch_task ~= nil then
        inst._watch_task:Cancel()
        inst._watch_task = nil
    end

    local hermit = inst._encounter_hermit
    if hermit ~= nil then
        if inst._on_hermit_removed ~= nil then
            inst:RemoveEventCallback("onremove", inst._on_hermit_removed, hermit)
            inst._on_hermit_removed = nil
        end

        if hermit:IsValid() then
            if victory and not hermit.pearlgiven then
                hermit.pearlgiven = true
                local pearl = SpawnPrefab("hermit_pearl")
                if pearl ~= nil then
                    pearl.Transform:SetPosition(inst.Transform:GetWorldPosition())
                    LearnPearlReward(hermit)
                else
                    hermit.pearlgiven = nil
                end
            end

            if hermit._hermitcrab_boss == inst then
                hermit._hermitcrab_boss = nil
            end

            if hermit:IsInLimbo() then
                hermit:ReturnToScene()
            end
        end
    end

    if inst._on_hermit_relocated ~= nil then
        inst:RemoveEventCallback("ms_hermitcrab_relocated", inst._on_hermit_relocated, TheWorld)
        inst._on_hermit_relocated = nil
    end

    if TheWorld._hermitcrab_boss == inst then
        TheWorld._hermitcrab_boss = nil
    end

    inst._encounter_hermit = nil

    if not already_removing and inst:IsValid() then
        inst:Remove()
    end
end

local function SetEncounterHermit(inst, hermit, challenger)
    inst._encounter_hermit = hermit
    inst.components.knownlocations:RememberLocation("home", inst:GetPosition())

    inst._on_hermit_removed = function()
        inst._encounter_hermit = nil
        inst._on_hermit_removed = nil
        if inst:IsValid() then
            inst:FinishEncounter(false)
        end
    end
    inst:ListenForEvent("onremove", inst._on_hermit_removed, hermit)

    inst._on_hermit_relocated = function()
        if inst:IsValid() then
            inst:FinishEncounter(false)
        end
    end
    inst:ListenForEvent("ms_hermitcrab_relocated", inst._on_hermit_relocated, TheWorld)

    if challenger ~= nil and challenger:IsValid() then
        inst.components.combat:SetTarget(challenger)
    end

    inst._watch_task = inst:DoPeriodicTask(WATCH_PERIOD, WatchEncounter, WATCH_PERIOD)
end

local function OnRemoveEntity(inst)
    inst:FinishEncounter(false, true)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    MakeCharacterPhysics(inst, 50, 0.5)

    inst.DynamicShadow:SetSize(1.5, 0.75)
    inst.Transform:SetFourFaced()

    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild("hermitcrab_build")
    inst.AnimState:PlayAnimation("idle_loop", true)
    inst.AnimState:Hide("ARM_carry")
    inst.AnimState:Hide("HAT")
    inst.AnimState:Hide("HAIR_HAT")
    inst.AnimState:Show("HAIR_NOHAT")
    inst.AnimState:Show("HAIR")
    inst.AnimState:Show("HEAD")
    inst.AnimState:Hide("HEAD_HAT")

    inst:AddTag("character")
    inst:AddTag("hostile")
    inst:AddTag("monster")
    inst:AddTag("epic")
    inst:AddTag("hermitcrab_boss")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst._empty_encounter_time = 0

    inst:AddComponent("inspectable")

    inst:AddComponent("locomotor")
    inst.components.locomotor.walkspeed = 3
    inst.components.locomotor.runspeed = 5

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(MAX_HEALTH)
    inst.components.health:SetMinHealth(1)

    inst:AddComponent("combat")
    inst.components.combat:SetDefaultDamage(DAMAGE)
    inst.components.combat:SetAttackPeriod(ATTACK_PERIOD)
    inst.components.combat:SetRange(1.5, 2)
    inst.components.combat:SetRetargetFunction(1, Retarget)
    inst.components.combat:SetKeepTargetFunction(KeepTarget)

    inst:AddComponent("knownlocations")

    inst:SetStateGraph("SGhermitcrab_boss")
    inst:SetBrain(brain)

    inst.SetEncounterHermit = SetEncounterHermit
    inst.FinishEncounter = FinishEncounter
    inst.OnRemoveEntity = OnRemoveEntity

    inst:ListenForEvent("healthdelta", OnHealthDelta)

    return inst
end

return Prefab("hermitcrab_boss", fn, assets, prefabs)
