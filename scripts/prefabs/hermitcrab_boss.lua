-- ============================================================================
-- Boss 实体：寄居蟹隐士（战斗形态）
-- 在战前场景移除后生成，战斗结束自动销毁，不持久化
-- ============================================================================

local brain = require("brains/hermitcrab_bossbrain")

-- 动画和音效资源
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

-- 掉落物：珍珠将在战斗胜利时生成
local prefabs =
{
    "hermit_pearl",
}

-- ============================================================================
-- 数值常量
-- ============================================================================
local MAX_HEALTH = 5200              -- 最大生命值
local DAMAGE = 40                    -- 攻击伤害
local ATTACK_PERIOD = 2              -- 攻击间隔（秒）
local TARGET_DISTANCE = 20           -- 索敌范围
local KEEP_TARGET_DISTANCE = 30      -- 丢失目标距离
local ENCOUNTER_DISTANCE = 35        -- 判定"附近有玩家"的距离
local EMPTY_ENCOUNTER_TIMEOUT = 10   -- 无玩家超时时间（秒），超时后战斗自动结束
local WATCH_PERIOD = 2               -- 检测周期（秒）

local TARGET_MUST_TAGS = { "player" }
local TARGET_CANT_TAGS = { "playerghost", "INLIMBO" }

-- ---------------------------------------------------------------------------
-- 索敌函数：在范围内寻找可攻击的玩家
-- ---------------------------------------------------------------------------
local function Retarget(inst)
    return FindEntity(inst, TARGET_DISTANCE, function(target)
        return inst.components.combat:CanTarget(target)
    end, TARGET_MUST_TAGS, TARGET_CANT_TAGS)
end

-- ---------------------------------------------------------------------------
-- 保持目标函数：目标必须存活且在追击范围内
-- ---------------------------------------------------------------------------
local function KeepTarget(inst, target)
    return target ~= nil
        and target:IsValid()
        and not target:HasTag("playerghost")
        and inst:IsNear(target, KEEP_TARGET_DISTANCE)
        and inst.components.combat:CanTarget(target)
end

-- ---------------------------------------------------------------------------
-- 检查附近是否有存活的玩家（用于无玩家超时判定）
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 定时检测：连续无玩家超时后自动结束战斗（视为失败）
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 投降（血量打到最低时触发）：停止战斗动作，进入投降动画
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 血量变化监听：血量降至最低时触发投降
-- 注意：使用 minhealth=1 实现"打到1血投降"而非击杀
-- ---------------------------------------------------------------------------
local function OnHealthDelta(inst)
    if inst.components.health.currenthealth <= inst.components.health.minhealth then
        BeginSurrender(inst)
    end
end

-- ---------------------------------------------------------------------------
-- 奖励：获胜时让寄居蟹学会冬季装饰珍珠配方
-- ---------------------------------------------------------------------------
local function LearnPearlReward(hermit)
    if hermit.components.craftingstation ~= nil
        and not hermit.components.craftingstation:KnowsItem("winter_ornament_boss_pearl") then
        hermit.components.craftingstation:LearnItem(
            "winter_ornament_boss_pearl",
            "hermitshop_winter_ornament_boss_pearl"
        )
    end
end

-- ---------------------------------------------------------------------------
-- 结束战斗：清理引用、归还寄居蟹、发放奖励、销毁 Boss
-- @param victory         true=玩家获胜，false=失败/中断
-- @param already_removing 已通过 onremove 触发销毁，避免重复 Remove()
-- ---------------------------------------------------------------------------
local function FinishEncounter(inst, victory, already_removing)
    if inst._encounter_resolved then
        return
    end

    inst._encounter_resolved = true

    -- 停止无玩家超时检测
    if inst._watch_task ~= nil then
        inst._watch_task:Cancel()
        inst._watch_task = nil
    end

    local hermit = inst._encounter_hermit
    if hermit ~= nil then
        -- 取消事件监听
        if inst._on_hermit_removed ~= nil then
            inst:RemoveEventCallback("onremove", inst._on_hermit_removed, hermit)
            inst._on_hermit_removed = nil
        end

        if hermit:IsValid() then
            if victory and not hermit.pearlgiven then
                -- 获胜奖励：掉落珍珠并解锁配方
                hermit.pearlgiven = true
                local pearl = SpawnPrefab("hermit_pearl")
                if pearl ~= nil then
                    pearl.Transform:SetPosition(inst.Transform:GetWorldPosition())
                    LearnPearlReward(hermit)
                else
                    hermit.pearlgiven = nil
                end
            end

            -- 清理寄居蟹身上的 Boss 引用
            if hermit._hermitcrab_boss == inst then
                hermit._hermitcrab_boss = nil
            end

            -- 将寄居蟹从 limbo 恢复回场景
            if hermit:IsInLimbo() then
                hermit:ReturnToScene()
            end
        end
    end

    -- 取消寄居蟹搬迁监听
    if inst._on_hermit_relocated ~= nil then
        inst:RemoveEventCallback("ms_hermitcrab_relocated", inst._on_hermit_relocated, TheWorld)
        inst._on_hermit_relocated = nil
    end

    -- 清理世界引用
    if TheWorld._hermitcrab_boss == inst then
        TheWorld._hermitcrab_boss = nil
    end

    inst._encounter_hermit = nil

    -- 销毁 Boss 实体（除非正在被引擎移除）
    if not already_removing and inst:IsValid() then
        inst:Remove()
    end
end

-- ---------------------------------------------------------------------------
-- 关联 Boss 与寄居蟹：绑定引用、设置事件监听、开始攻击
-- ---------------------------------------------------------------------------
local function SetEncounterHermit(inst, hermit, challenger)
    inst._encounter_hermit = hermit

    -- 记录出生位置作为"家"（用于 Leash 行为）
    inst.components.knownlocations:RememberLocation("home", inst:GetPosition())

    -- 如果寄居蟹被移除（例如被指令移除），强制结束战斗
    inst._on_hermit_removed = function()
        inst._encounter_hermit = nil
        inst._on_hermit_removed = nil
        if inst:IsValid() then
            inst:FinishEncounter(false)
        end
    end
    inst:ListenForEvent("onremove", inst._on_hermit_removed, hermit)

    -- 如果寄居蟹搬迁，结束战斗
    inst._on_hermit_relocated = function()
        if inst:IsValid() then
            inst:FinishEncounter(false)
        end
    end
    inst:ListenForEvent("ms_hermitcrab_relocated", inst._on_hermit_relocated, TheWorld)

    -- 如果有挑战者，立即将其设为目标
    if challenger ~= nil and challenger:IsValid() then
        inst.components.combat:SetTarget(challenger)
    end

    -- 启动无玩家超时检测
    inst._watch_task = inst:DoPeriodicTask(WATCH_PERIOD, WatchEncounter, WATCH_PERIOD)
end

-- ---------------------------------------------------------------------------
-- 实体被移除时清理战斗状态
-- ---------------------------------------------------------------------------
local function OnRemoveEntity(inst)
    inst:FinishEncounter(false, true)
end

-- ============================================================================
-- 实体创建入口
-- ============================================================================
local function fn()
    local inst = CreateEntity()

    -- 基础组件
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    -- 碰撞体积
    MakeCharacterPhysics(inst, 50, 0.5)

    inst.DynamicShadow:SetSize(1.5, 0.75)
    inst.Transform:SetFourFaced()

    -- 使用寄居蟹的 build，Wilson 的骨骼动画
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

    -- 标签：character 代表角色生物，epic 用于巨兽判定
    inst:AddTag("character")
    inst:AddTag("hostile")
    inst:AddTag("monster")
    inst:AddTag("epic")
    inst:AddTag("hermitcrab_boss")

    inst.entity:SetPristine()

    -- 客户端只需要实体外观，不需要逻辑
    if not TheWorld.ismastersim then
        return inst
    end

    -- =========================
    -- 服务器端逻辑
    -- =========================

    -- 战斗实体不持久化（不存档）
    inst.persists = false
    inst._empty_encounter_time = 0

    inst:AddComponent("inspectable")

    -- 移动组件
    inst:AddComponent("locomotor")
    inst.components.locomotor.walkspeed = 3
    inst.components.locomotor.runspeed = 5

    -- 生命值：最大 1500，最低 1（不会死亡，打到 1 血后投降）
    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(MAX_HEALTH)
    inst.components.health:SetMinHealth(1)

    -- 战斗组件
    inst:AddComponent("combat")
    inst.components.combat:SetDefaultDamage(DAMAGE)
    inst.components.combat:SetAttackPeriod(ATTACK_PERIOD)
    inst.components.combat:SetRange(1.5, 2)
    inst.components.combat:SetRetargetFunction(1, Retarget)
    inst.components.combat:SetKeepTargetFunction(KeepTarget)

    -- 位置记忆（用于 Leash 回家行为）
    inst:AddComponent("knownlocations")

    -- 行为树和动画状态机
    inst:SetStateGraph("SGhermitcrab_boss")
    inst:SetBrain(brain)

    -- 暴露接口供外部调用
    inst.SetEncounterHermit = SetEncounterHermit
    inst.FinishEncounter = FinishEncounter
    inst.OnRemoveEntity = OnRemoveEntity

    -- 监听血量变化，触发投降判定
    inst:ListenForEvent("healthdelta", OnHealthDelta)

    return inst
end

return Prefab("hermitcrab_boss", fn, assets, prefabs)
