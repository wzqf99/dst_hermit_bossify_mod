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
    Asset("ANIM", "anim/player_actions_uniqueitem.zip"),
    Asset("ANIM", "anim/player_hermitcrab_idle.zip"),
    Asset("ANIM", "anim/player_hermitcrab_walk.zip"),
    Asset("ANIM", "anim/player_hermitcrab_look.zip"),
    Asset("ANIM", "anim/hermitcrab_build.zip"),
    Asset("ANIM", "anim/swap_trident.zip"),
    Asset("SOUND", "sound/sfx.fsb"),
    Asset("SOUND", "sound/wilson.fsb"),
}

-- 掉落物：珍珠将在战斗胜利时生成
local prefabs =
{
    "hermit_pearl",
    "crab_king_waterspout",
    "hermitcrab_boss_shell",
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
local SHELL_PHASE_HEALTH = 0.75      -- 贝壳环绕阶段触发血量
local SHELL_COUNT = 6                -- 喷水柱和环绕贝壳数量
local ISLAND_WATER_MIN_RADIUS = 22   -- 从奶奶岛中心寻找水面的最小半径
local ISLAND_WATER_MAX_RADIUS = 40   -- 从奶奶岛中心寻找水面的最大半径
local ISLAND_WATER_FALLBACK_RADIUS = 55 -- 不规则/搬迁岛屿的扩大搜索半径
local WATER_POINT_MIN_SPACING = 5    -- 喷水柱之间的最小间距
local WATERSPOUT_DAMAGE = TUNING.TRIDENT.SPELL.DAMAGE -- 复用原版三叉戟法术伤害
local WATERSPOUT_DAMAGE_RADIUS = TUNING.TRIDENT.SPELL.RADIUS
local SHELL_CONTACT_DAMAGE = DAMAGE  -- 环绕贝壳每次接触的伤害
local SHELL_CONTACT_COOLDOWN = 1     -- 同一目标受到任意贝壳伤害后的保护时间

local TARGET_MUST_TAGS = { "player" }
local TARGET_CANT_TAGS = { "playerghost", "INLIMBO" }

local function CanDamageTarget(inst, target)
    return target ~= nil
        and target:IsValid()
        and target ~= inst
        and target.components.combat ~= nil
        and target.components.health ~= nil
        and not target.components.health:IsDead()
        and not target:HasTag("wall")
        and not target:HasTag("structure")
        and inst.components.combat:CanTarget(target)
end

-- crab_king_waterspout 只是视觉特效，原版三叉戟的实际伤害需要由施法方处理。
local function DoWaterspoutDamage(inst, point, waterspout, hit_targets)
    local x, y, z = point:Get()
    for _, target in ipairs(TheSim:FindEntities(
        x,
        y,
        z,
        WATERSPOUT_DAMAGE_RADIUS + 1,
        TARGET_MUST_TAGS,
        TARGET_CANT_TAGS
    )) do
        local radius = WATERSPOUT_DAMAGE_RADIUS + target:GetPhysicsRadius(0)
        local target_x, _, target_z = target.Transform:GetWorldPosition()
        local dx = target_x - x
        local dz = target_z - z
        if not hit_targets[target]
            and dx * dx + dz * dz <= radius * radius
            and CanDamageTarget(inst, target) then
            if target.components.combat:GetAttacked(
                inst,
                WATERSPOUT_DAMAGE,
                waterspout
            ) then
                hit_targets[target] = true
            end
        end
    end
end

-- 六枚贝壳共用伤害冷却；冷却期间的新接触仍是有效碰撞。
local function TryShellContactHit(inst, shell, target)
    if inst._encounter_resolved
        or inst._surrendering
        or not CanDamageTarget(inst, target) then
        return false
    end

    local now = GetTime()
    inst._shell_hit_cooldowns = inst._shell_hit_cooldowns or {}
    if (inst._shell_hit_cooldowns[target] or 0) > now then
        return true
    end

    if target.components.combat:GetAttacked(inst, SHELL_CONTACT_DAMAGE, shell) then
        inst._shell_hit_cooldowns[target] = now + SHELL_CONTACT_COOLDOWN
        target:PushEvent("knockback", {
            knocker = shell,
            radius = shell:GetPhysicsRadius(0.75) + target:GetPhysicsRadius(0),
            strengthmult = 0.45,
            forcelanded = true,
        })
    end

    return true
end

local function IsFarEnoughFromWaterPoints(points, x, z)
    local min_distance_sq = WATER_POINT_MIN_SPACING * WATER_POINT_MIN_SPACING
    for _, point in ipairs(points) do
        local dx = point.x - x
        local dz = point.z - z
        if dx * dx + dz * dz < min_distance_sq then
            return false
        end
    end

    return true
end

local function TryAddWaterPoint(points, x, z)
    if TheWorld.Map:IsOceanAtPoint(x, 0, z, false)
        and IsFarEnoughFromWaterPoints(points, x, z) then
        table.insert(points, Vector3(x, 0, z))
        return true
    end

    return false
end

-- 在奶奶岛外围的六个扇区分别取点，避免随机结果全挤在同一侧。
local function FindIslandWaterPoints(inst)
    local center = inst._island_center or inst:GetPosition()
    local points = {}
    local sector = TWOPI / SHELL_COUNT
    local start_angle = math.random() * TWOPI

    for index = 1, SHELL_COUNT do
        local sector_angle = start_angle + (index - 1) * sector
        for _ = 1, 30 do
            local angle = sector_angle + (math.random() - 0.5) * sector * 0.8
            local radius = ISLAND_WATER_MIN_RADIUS
                + math.random() * (ISLAND_WATER_MAX_RADIUS - ISLAND_WATER_MIN_RADIUS)
            local x = center.x + radius * math.cos(angle)
            local z = center.z - radius * math.sin(angle)
            if TryAddWaterPoint(points, x, z) then
                break
            end
        end
    end

    -- 岛屿形状不规则时，再进行不分扇区的兜底搜索。
    for _ = 1, 300 do
        if #points >= SHELL_COUNT then
            break
        end

        local angle = math.random() * TWOPI
        local radius = ISLAND_WATER_MIN_RADIUS
            + math.random() * (ISLAND_WATER_MAX_RADIUS - ISLAND_WATER_MIN_RADIUS)
        TryAddWaterPoint(
            points,
            center.x + radius * math.cos(angle),
            center.z - radius * math.sin(angle)
        )
    end

    -- 随机采样仍不足时，按同一个随机起始角做环形扫描，保证标准岛屿凑齐六点。
    local radius = ISLAND_WATER_MIN_RADIUS
    while #points < SHELL_COUNT and radius <= ISLAND_WATER_FALLBACK_RADIUS do
        for step = 0, 71 do
            local angle = start_angle + step * TWOPI / 72
            TryAddWaterPoint(
                points,
                center.x + radius * math.cos(angle),
                center.z - radius * math.sin(angle)
            )
            if #points >= SHELL_COUNT then
                break
            end
        end
        radius = radius + 1
    end

    return points
end

local function SpawnShellRing(inst)
    if inst._shell_phase_released or inst._encounter_resolved or inst._surrendering then
        return
    end

    inst._shell_phase_released = true
    inst._orbit_shells = inst._orbit_shells or {}

    local points = FindIslandWaterPoints(inst)
    local orbit_start_angle = math.random() * TWOPI
    local waterspout_hit_targets = {}
    for index, point in ipairs(points) do
        local waterspout = SpawnPrefab("crab_king_waterspout")
        if waterspout ~= nil then
            waterspout.Transform:SetPosition(point:Get())
        end
        DoWaterspoutDamage(inst, point, waterspout, waterspout_hit_targets)

        local shell = SpawnPrefab("hermitcrab_boss_shell")
        if shell ~= nil then
            shell.Transform:SetPosition(point:Get())
            shell:SetBoss(inst, index, SHELL_COUNT, orbit_start_angle)
            table.insert(inst._orbit_shells, shell)
        end
    end
end

local function BeginShellPhase(inst)
    if inst._shell_phase_triggered or inst._encounter_resolved or inst._surrendering then
        return
    end

    inst._shell_phase_triggered = true
    inst.components.combat:CancelAttack()
    inst:PushEvent("hermitboss_shell_phase")
end

local function RemoveOrbitShells(inst)
    if inst._orbit_shells == nil then
        return
    end

    for _, shell in ipairs(inst._orbit_shells) do
        if shell:IsValid() then
            shell:Remove()
        end
    end
    inst._orbit_shells = nil
end

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
local function OnHealthDelta(inst, data)
    if inst.components.health.currenthealth <= inst.components.health.minhealth then
        BeginSurrender(inst)
    elseif not inst._shell_phase_triggered
        and data ~= nil
        and data.oldpercent > SHELL_PHASE_HEALTH
        and data.newpercent <= SHELL_PHASE_HEALTH then
        BeginShellPhase(inst)
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

    -- 环绕物只属于本场战斗，不掉落，也不影响原版清理水中垃圾任务。
    RemoveOrbitShells(inst)

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

    -- 优先使用奶奶岛中心标记，让喷水柱分布在整座岛的外围。
    local island_marker = hermit.CHEVO_marker
    if island_marker == nil or not island_marker:IsValid() then
        island_marker = FindEntity(hermit, 35, nil, { "hermitcrab_marker" })
    end
    inst._island_center = island_marker ~= nil and island_marker:GetPosition() or inst:GetPosition()

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

    -- 生命值：最大 5200，最低 1（不会死亡，打到 1 血后投降）
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
    inst.SpawnShellRing = SpawnShellRing
    inst.TryShellContactHit = TryShellContactHit
    inst.FinishEncounter = FinishEncounter
    inst.OnRemoveEntity = OnRemoveEntity

    -- 监听血量变化，触发投降判定
    inst:ListenForEvent("healthdelta", OnHealthDelta)

    return inst
end

return Prefab("hermitcrab_boss", fn, assets, prefabs)
