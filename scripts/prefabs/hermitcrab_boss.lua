-- Boss 实体：只负责外观、基础战斗组件和功能模块装配。
local brain = require("brains/hermitcrab_bossbrain")
local encounter = require("hermitcrab_boss/encounter")
local kelp_snare = require("hermitcrab_boss/skills/kelp_snare")
local shell_ring = require("hermitcrab_boss/skills/shell_ring")
local guard_summon = require("hermitcrab_boss/skills/guard_summon")
local final_phase = require("hermitcrab_boss/skills/final_phase")
local fissure = require("hermitcrab_boss/fissure")
local tuning = require("hermitcrab_boss/tuning")

local assets =
{
    Asset("ANIM", "anim/player_basic.zip"),
    Asset("ANIM", "anim/player_actions.zip"),
    Asset("ANIM", "anim/player_actions_item.zip"),
    Asset("ANIM", "anim/player_actions_uniqueitem.zip"),
    Asset("ANIM", "anim/player_hermitcrab_idle.zip"),
    Asset("ANIM", "anim/player_hermitcrab_walk.zip"),
    Asset("ANIM", "anim/player_hermitcrab_look.zip"),
    Asset("ANIM", "anim/hermitcrab_build.zip"),
    Asset("ANIM", "anim/swap_trident.zip"),
    Asset("SOUND", "sound/sfx.fsb"),
    Asset("SOUND", "sound/wilson.fsb"),
}

local prefabs = {}
local prefab_names = {}

local function AddModulePrefabs(module)
    for _, prefab in ipairs(module.PREFABS or {}) do
        if not prefab_names[prefab] then
            prefab_names[prefab] = true
            table.insert(prefabs, prefab)
        end
    end
end

AddModulePrefabs(encounter)
AddModulePrefabs(kelp_snare)
AddModulePrefabs(shell_ring)
AddModulePrefabs(guard_summon)
AddModulePrefabs(final_phase)

local TARGET_MUST_TAGS = { "player" }
local TARGET_CANT_TAGS = { "playerghost", "INLIMBO" }

local function Retarget(inst)
    return FindEntity(inst, tuning.TARGET_DISTANCE, function(target)
        return inst.components.combat:CanTarget(target)
    end, TARGET_MUST_TAGS, TARGET_CANT_TAGS)
end

local function KeepTarget(inst, target)
    return target ~= nil
        and target:IsValid()
        and not target:HasTag("playerghost")
        and inst:IsNear(target, tuning.KEEP_TARGET_DISTANCE)
        and inst.components.combat:CanTarget(target)
end

local function ConfigureAppearance(inst)
    inst.DynamicShadow:SetSize(1.5, 0.75)
    inst.Transform:SetFourFaced()

    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild("hermitcrab_build")
    inst.AnimState:PlayAnimation("idle_loop", true)
    inst.AnimState:OverrideSymbol("swap_object", "swap_trident", "swap_trident")
    inst.AnimState:OverrideSymbol("swap_trident", "swap_trident", "swap_trident")
    inst.AnimState:Show("ARM_carry")
    inst.AnimState:Hide("ARM_normal")
    inst.AnimState:Hide("HAT")
    inst.AnimState:Hide("HAIR_HAT")
    inst.AnimState:Show("HAIR_NOHAT")
    inst.AnimState:Show("HAIR")
    inst.AnimState:Show("HEAD")
    inst.AnimState:Hide("HEAD_HAT")
end

local function ConfigureServerComponents(inst)
    inst:AddComponent("inspectable")

    inst:AddComponent("locomotor")
    inst.components.locomotor.walkspeed = 3
    inst.components.locomotor.runspeed = 5

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(tuning.MAX_HEALTH)
    inst.components.health:SetMinHealth(1)

    inst:AddComponent("combat")
    inst.components.combat:SetDefaultDamage(tuning.DAMAGE)
    inst.components.combat:SetAttackPeriod(tuning.ATTACK_PERIOD)
    inst.components.combat:SetRange(1.5, 2)
    inst.components.combat:SetRetargetFunction(1, Retarget)
    inst.components.combat:SetKeepTargetFunction(KeepTarget)

    inst:AddComponent("knownlocations")
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    MakeCharacterPhysics(inst, 50, 0.5)
    ConfigureAppearance(inst)

    inst:AddTag("character")
    inst:AddTag("hostile")
    inst:AddTag("monster")
    inst:AddTag("epic")
    inst:AddTag("hermitcrab_boss")
    -- 标记为蟹卫友军，避免召唤出的蟹卫把 Boss 当作目标攻击。
    inst:AddTag("crabking_ally")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    ConfigureServerComponents(inst)

    inst:SetStateGraph("SGhermitcrab_boss")
    inst:SetBrain(brain)

    -- 最终阶段先监听，保证跨过 30% 的高额伤害不会直接触发旧投降结算。
    final_phase.Attach(inst, encounter.FINISHING_EVENT)
    encounter.Attach(inst)
    fissure.Attach(inst, encounter.FINISHED_EVENT)
    kelp_snare.Attach(inst, encounter.FINISHED_EVENT, final_phase.STARTED_EVENT)
    shell_ring.Attach(inst, encounter.FINISHED_EVENT, final_phase.STARTED_EVENT)
    guard_summon.Attach(inst, encounter.FINISHED_EVENT, final_phase.STARTED_EVENT)

    return inst
end

return Prefab("hermitcrab_boss", fn, assets, prefabs)
