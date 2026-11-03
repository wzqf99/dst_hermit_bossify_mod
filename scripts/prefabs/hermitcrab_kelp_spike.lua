-- ============================================================================
-- 海带骨刺实体（方案 A：海带植株 bullkelp 的竖立形态）
-- 用海带植株竖着长的形态，模拟远古织影者的"地面骨刺"：
--   出现（grow 生长动画）→ 竖立存在（idle 循环）→ 枯萎缩回（picked 动画）
--
-- 伤害：定格瞬间对范围内玩家结算一次（一次性），由施法者（Boss）造成，
--       保证仇恨与击杀归属正确。同一玩家在 SPIKE_HIT_COOLDOWN 内最多被命中一次，
--       避免牢笼一圈刺同时定格时叠出多倍伤害。
--
-- 碰撞：定格后可开启物理碰撞体积（blocking），把玩家真正围在牢笼里；
--       未开启的刺（螺旋 / 房屋）只有视觉，不阻挡任何角色。
--
-- 依赖：
--   - bullkelp.zip（海带植株动画，含 idle / grow / picking / picked）
--   - erode_ash.zip（消失灰烬特效）
-- 生成后调用 :RestartSpike(delay, duration, variation) 控制冒出时序。
-- ============================================================================

local assets =
{
    Asset("ANIM", "anim/bullkelp.zip"),
    Asset("ANIM", "anim/erode_ash.zip"),
    Asset("SOUND", "sound/common.fsb"),
}

local prefabs =
{
    "erode_ash",
}

local DEFAULT_DURATION = 6
local DEFAULT_DAMAGE = 40
local DEFAULT_CONTACT_RADIUS = 1.6
local DEFAULT_CONTACT_COOLDOWN = 1
local DEFAULT_GROW_SPEED = 1
local DEFAULT_GROW_FREEZE_PROGRESS = 0.3
local FREEZE_MULTIPLIER = 0.0001
local DEFAULT_COLLISION_RADIUS = 0.35

--------------------------------------------------------------------------
-- 抛飞掉落物（复用原版骨刺的"顶飞物品"效果）
--------------------------------------------------------------------------
local function SpikeLaunch(item, launcher, basespeed, startheight, startradius)
    local x0, y0, z0 = launcher.Transform:GetWorldPosition()
    local x1, y1, z1 = item.Transform:GetWorldPosition()
    local dx, dz = x1 - x0, z1 - z0
    local dsq = dx * dx + dz * dz
    local angle
    if dsq > 0 then
        local dist = math.sqrt(dsq)
        angle = math.atan2(dz / dist, dx / dist) + (math.random() * 20 - 10) * DEGREES
    else
        angle = TWOPI * math.random()
    end
    local sina, cosa = math.sin(angle), math.cos(angle)
    local speed = basespeed + math.random()
    TryTeleportToLaunchPos(item, x0 + startradius * cosa, startheight, z0 + startradius * sina)
    item.Physics:SetVel(cosa * speed, speed * 5 + math.random() * 2, sina * speed)
end

local COLLAPSIBLE_WORK_ACTIONS =
{
    CHOP = true,
    DIG = true,
    HAMMER = true,
    MINE = true,
}
local COLLAPSIBLE_TAGS = { "_combat", "pickable", "NPC_workable" }
for k, v in pairs(COLLAPSIBLE_WORK_ACTIONS) do
    table.insert(COLLAPSIBLE_TAGS, k .. "_workable")
end
local NON_COLLAPSIBLE_TAGS =
{
    "hermitcrab_boss", "flying", "shadow", "playerghost", "FX", "NOCLICK", "DECOR", "INLIMBO",
}
local TOSSITEM_MUST_TAGS = { "_inventoryitem" }
local TOSSITEM_CANT_TAGS = { "locomotor", "INLIMBO" }

--------------------------------------------------------------------------
-- 出现瞬间：清理脚下可摧毁物、顶飞掉落物（不影响玩家，玩家伤害走接触逻辑）。
--------------------------------------------------------------------------
local function DoClear(inst)
    local x, _, z = inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(
        x, 0, z,
        DEFAULT_CONTACT_RADIUS,
        nil, NON_COLLAPSIBLE_TAGS, COLLAPSIBLE_TAGS
    )
    for i, v in ipairs(ents) do
        if v:IsValid() and v ~= inst.attacker then
            local isworkable = false
            if v.components.workable ~= nil then
                local work_action = v.components.workable:GetWorkAction()
                isworkable = (
                    (work_action == nil and v:HasTag("NPC_workable")) or
                    (v.components.workable:CanBeWorked() and work_action ~= nil and COLLAPSIBLE_WORK_ACTIONS[work_action.id])
                )
            end
            if isworkable then
                v.components.workable:Destroy(inst)
                if v:IsValid() and v:HasTag("stump") then
                    v:Remove()
                end
            elseif v.components.pickable ~= nil
                and v.components.pickable:CanBePicked()
                and not v:HasTag("intense") then
                v.components.pickable:Pick(inst)
            end
        end
    end

    local totoss = TheSim:FindEntities(
        x, 0, z,
        DEFAULT_CONTACT_RADIUS,
        TOSSITEM_MUST_TAGS, TOSSITEM_CANT_TAGS
    )
    for i, v in ipairs(totoss) do
        DeactivateInventoryItemBeforeLaunch(v)
        if not v.components.inventoryitem.nobounce and v.Physics ~= nil and v.Physics:IsActive() then
            SpikeLaunch(v, inst, 0.8 + 0.2, 0.2 * 0.4, 0.2 + v:GetPhysicsRadius(0))
        end
    end
end

--------------------------------------------------------------------------
-- 一次性伤害：只在"定格瞬间"结算一次，不再周期性检测。
-- 同一玩家在 contact_cooldown 内最多被一次海带刺命中：牢笼一圈 6 根刺
-- 几乎同时定格，若各自独立结算会叠出 6 倍伤害，所以冷却表挂在世界层面、
-- 由所有海带刺共享（弱键，实体移除后自动失效）。
--------------------------------------------------------------------------
local function GetHitCooldowns()
    local world = TheWorld
    if world._kelp_spike_hit_cooldowns == nil then
        world._kelp_spike_hit_cooldowns = setmetatable({}, { __mode = "k" })
    end
    return world._kelp_spike_hit_cooldowns
end

local function DealSpikeDamage(inst)
    local attacker = inst.attacker
    if attacker == nil
        or not attacker:IsValid()
        or attacker._encounter_resolved
        or attacker._surrendering then
        return
    end

    local x, _, z = inst.Transform:GetWorldPosition()
    local radius = inst.contact_radius or DEFAULT_CONTACT_RADIUS
    local now = GetTime()
    local cooldowns = GetHitCooldowns()

    for _, target in ipairs(TheSim:FindEntities(
        x, 0, z, radius + 1,
        { "player" }, { "playerghost", "INLIMBO" }
    )) do
        if target:IsValid()
            and target ~= attacker
            and target.components.combat ~= nil
            and target.components.health ~= nil
            and not target.components.health:IsDead()
            and (cooldowns[target] or 0) <= now then

            local tr = target:GetPhysicsRadius(0)
            local tx, _, tz = target.Transform:GetWorldPosition()
            local dx = tx - x
            local dz = tz - z
            local r = radius + tr
            if dx * dx + dz * dz <= r * r then
                if target.components.combat:GetAttacked(
                    attacker,
                    inst.contact_damage or DEFAULT_DAMAGE,
                    inst
                ) then
                    cooldowns[target] = now + (inst.contact_cooldown or DEFAULT_CONTACT_COOLDOWN)
                    -- 有碰撞体积的刺（牢笼）不击退：玩家已被围住，击退只会
                    -- 把人顶在刺上反复挤压。纯视觉的刺保留原版顶飞手感。
                    if not inst.blocking then
                        target:PushEvent("knockback", {
                            knocker = inst,
                            radius = r,
                            strengthmult = 0.35,
                            forcelanded = true,
                        })
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- 生命周期：
--   picked（光球）→ grow（冒出，减速）→ 定格在 grow 指定进度（叶子刚出芽）
--   → picked（枯萎）→ erode（消散）
--------------------------------------------------------------------------
local function ErodeAndRemove(inst)
    if inst:IsValid() then
        ErodeAway(inst, 1)
    end
end

local function KillSpike(inst)
    inst.killtask = nil
    if inst.killed then
        return
    end

    inst.killed = true

    if inst.freezetask ~= nil then
        inst.freezetask:Cancel()
        inst.freezetask = nil
    end

    -- 立即取消碰撞体积，让枯萎缩回阶段不再阻挡玩家（纯视觉刺没有物理体）。
    if inst.Physics ~= nil then
        inst.Physics:SetActive(false)
    end

    -- 恢复原速，让枯萎动画正常播放，随后消失。
    inst.AnimState:SetDeltaTimeMultiplier(1)
    inst.AnimState:PlayAnimation("picked")
    inst.SoundEmitter:PlaySound("turnoftides/common/together/water/harvest_plant")
    inst:ListenForEvent("animover", ErodeAndRemove)

    -- 兜底：动画异常时也能移除。
    inst:DoTaskInTime(1.5, function(inst)
        if inst:IsValid() then
            inst:Remove()
        end
    end)
end

-- grow 播放到指定进度时触发：冻结定格在"叶子长到最高"的骨刺姿态，
-- 并从这一刻起结算唯一的一次伤害。
local function FreezeSpike(inst)
    inst.freezetask = nil
    if inst.killed or not inst:IsValid() then
        return
    end

    -- 用极小倍率冻结动画，定格在 grow 当前帧（约 GROW_FREEZE_PROGRESS 进度）。
    inst.AnimState:SetDeltaTimeMultiplier(FREEZE_MULTIPLIER)
    inst.SoundEmitter:PlaySound("turnoftides/common/together/water/harvest_plant")
    DoClear(inst)

    -- 一次性伤害：定格瞬间结算一次，之后不再持续掉血。
    DealSpikeDamage(inst)

    -- 存活时间从定格开始算（定格阶段共 duration 秒），期间不再造成伤害。
    inst.killtask = inst:DoTaskInTime(inst.duration or DEFAULT_DURATION, KillSpike)
end

local function StartSpike(inst)
    inst.task = nil

    inst.AnimState:PlayAnimation("grow")
    local grow_length = inst.AnimState:GetCurrentAnimationLength()
    local mult = inst.grow_speed or DEFAULT_GROW_SPEED
    inst.AnimState:SetDeltaTimeMultiplier(mult)

    -- grow 生长过程中不造成伤害，仅在播放到指定进度时冻结定格（FreezeSpike 内才开始伤害）。
    local progress = inst.grow_freeze_progress or DEFAULT_GROW_FREEZE_PROGRESS
    local freeze_at = grow_length * progress / mult
    inst.freezetask = inst:DoTaskInTime(freeze_at, FreezeSpike)
end

-- 延迟冒出；variation 用于制造缩放/颜色错落感。
local function RestartSpike(inst, delay, duration, variation)
    if inst.task ~= nil then
        inst.task:Cancel()
        if variation == nil then
            variation = math.random(1, 7)
        end
        inst.duration = duration or DEFAULT_DURATION

        -- 用 variation 生成缩放与颜色差异，让海带刺不显得整齐划一。
        local scale = 0.9 + (variation % 4) * 0.08
        inst.AnimState:SetScale(scale, scale, scale)
        local tint = 0.8 + (variation % 5) * 0.05
        inst.AnimState:SetMultColour(tint, tint, tint, 1)

        inst.task = inst:DoTaskInTime(delay or 0, StartSpike)
    end
end

-- 两个 prefab 共用同一套逻辑：
--   fn              纯视觉刺（螺旋 / 房屋）：完全没有物理体，保持原行为。
--   fn_wall         牢笼刺：出生即带障碍物理（参考原版 alterguardian_phase2spike 的骨刺墙）。
-- 拆成两个 prefab 是为了让"加物理"这件事完全不参与普通刺的创建流程。
local function MakeFn(with_physics)
    return function()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddDynamicShadow()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()

        if with_physics then
            -- 与原版骨刺墙一致：mass 0 静态障碍，挡角色 / 物品 / 巨兽，
            -- 实体睡眠时也保留物理体（否则远处的牢笼会失效）。
            MakeObstaclePhysics(inst, DEFAULT_COLLISION_RADIUS)
            inst.Physics:SetDontRemoveOnSleep(true)
        end

        inst.AnimState:SetBank("bullkelp")
        inst.AnimState:SetBuild("bullkelp")
        -- 初始为"被采摘"的空状态，等 RestartSpike 的延迟结束后再播 grow 冒出。
        inst.AnimState:PlayAnimation("picked")
        inst.AnimState:SetFinalOffset(1)

        inst.DynamicShadow:SetSize(1.2, 0.75)

        inst:AddTag("notarget")
        inst:AddTag("fossilspike")
        inst:AddTag("NOCLICK")

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst.persists = false
        inst.attacker = nil
        inst.duration = DEFAULT_DURATION
        inst.contact_damage = DEFAULT_DAMAGE
        inst.contact_radius = DEFAULT_CONTACT_RADIUS
        inst.contact_cooldown = DEFAULT_CONTACT_COOLDOWN
        inst.grow_speed = DEFAULT_GROW_SPEED
        inst.grow_freeze_progress = DEFAULT_GROW_FREEZE_PROGRESS
        inst.blocking = with_physics
        inst.collision_radius = DEFAULT_COLLISION_RADIUS

        -- 随机朝向，避免海带刺方向一致。
        inst.Transform:SetRotation(math.random() * 360)

        inst.task = inst:DoTaskInTime(0, StartSpike)
        inst.RestartSpike = RestartSpike
        inst.KillSpike = KillSpike

        -- 由技能模块在生成时设置施法者（Boss），用于伤害归属与排除自身。
        inst.SetAttacker = function(self, attacker)
            self.attacker = attacker
        end

        return inst
    end
end

return Prefab("hermitcrab_kelp_spike", MakeFn(false), assets, prefabs),
    Prefab("hermitcrab_kelp_spike_wall", MakeFn(true), assets, prefabs)
