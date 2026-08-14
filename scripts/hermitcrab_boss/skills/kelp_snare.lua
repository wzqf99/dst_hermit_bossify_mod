-- ============================================================================
-- 海带骨刺技能：血量降至 90% 时触发。
-- 用"竖立的海带"（海带植株 bullkelp 的竖立形态）模拟远古织影者的两个技能：
--   1. Snare 骨刺牢笼：围绕目标一圈竖立海带，形成牢笼并造成接触伤害。
--   2. Spikes 螺旋骨刺：从 Boss 脚下螺旋扩散的竖立海带，逐个延迟冒出。
-- 视觉实体复用 hermitcrab_kelp_spike（海带植株竖立形态）。
-- ============================================================================

local tuning = require("hermitcrab_boss/tuning").KELP_SNARE

local KelpSnare =
{
    PREFABS =
    {
        "hermitcrab_kelp_spike",
        "hermitcrab_web_ground",
    },
}

-- 玩家目标过滤
local PLAYER_MUST_TAGS = { "player" }
local PLAYER_CANT_TAGS = { "playerghost", "INLIMBO" }

local KELPSPIKE_TAGS = { "fossilspike" }

--------------------------------------------------------------------------
-- 通用：在指定点生成一根海带骨刺
--------------------------------------------------------------------------
local function SpawnSpikeAt(inst, x, z, variation, duration, delay)
    local spike = SpawnPrefab("hermitcrab_kelp_spike")
    if spike == nil then
        return nil
    end

    spike.Transform:SetPosition(x, 0, z)
    spike:SetAttacker(inst)

    -- 传入接触伤害参数（由 Boss 造成）。
    spike.contact_damage = tuning.SPIKE_DAMAGE
    spike.contact_radius = tuning.SPIKE_CONTACT_RADIUS
    spike.contact_cooldown = tuning.SPIKE_CONTACT_COOLDOWN
    -- 冒出动画速度倍率。
    spike.grow_speed = tuning.GROW_SPEED
    -- 冒出动画定格进度（长到该比例就冻结）。
    spike.grow_freeze_progress = tuning.GROW_FREEZE_PROGRESS

    local v = variation or math.random(7)
    if spike.RestartSpike ~= nil then
        spike:RestartSpike(delay or 0, duration or tuning.SPIKE_DURATION, v)
    end

    return spike
end

--------------------------------------------------------------------------
-- 骨刺不重叠检测（避免海带刺叠在同一处）
--------------------------------------------------------------------------
local function NoOverlap(x, z, r)
    return #TheSim:FindEntities(x, 0, z, r or 1, KELPSPIKE_TAGS) <= 0
end

--------------------------------------------------------------------------
-- 效果一：骨刺牢笼（Snare）
-- 参考原版 SpawnSnares：围绕每个目标一圈骨刺，形成牢笼。
--------------------------------------------------------------------------
local function FindSnareTargets(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local targets = {}
    local priority_index = 1

    for i, v in ipairs(TheSim:FindEntities(x, y, z, tuning.SNARE_RANGE, PLAYER_MUST_TAGS, PLAYER_CANT_TAGS)) do
        if v.components.health ~= nil and not v.components.health:IsDead() then
            table.insert(targets, priority_index, v)
            priority_index = priority_index + 1
        end
    end

    return #targets > 0 and targets or nil
end

local function SpawnSnareRing(inst, target)
    local x, _, z = target.Transform:GetWorldPosition()
    local is_large = target:HasTag("largecreature")
    local radius = target:GetPhysicsRadius(0) + (is_large and 1.5 or 0.5)
    local num = is_large and 12 or 6
    local dtheta = TWOPI / num

    local variation_pool = { 1, 2, 3, 4, 5, 6, 7 }
    local used = {}
    local queued = {}
    local delay_toggle = 0
    local map = TheWorld.Map

    for theta = math.random() * dtheta, TWOPI, dtheta do
        local x1 = x + radius * math.cos(theta)
        local z1 = z + radius * math.sin(theta)
        if map:IsPassableAtPoint(x1, 0, z1) and not map:IsPointNearHole(Vector3(x1, 0, z1)) then
            local variation = table.remove(variation_pool, math.random(#variation_pool))
            table.insert(used, variation)
            if #used > 3 then
                table.insert(queued, table.remove(used, 1))
            end
            if #variation_pool <= 0 then
                local swap = variation_pool
                variation_pool = queued
                queued = swap
            end

            -- 交替延迟，制造"依次冒出"的节奏。
            local delay = delay_toggle == 0 and 0 or (0.2 + delay_toggle * math.random() * 0.2)
            delay_toggle = delay_toggle == 1 and -1 or 1

            SpawnSpikeAt(inst, x1, z1, variation, tuning.SPIKE_DURATION, delay)
        end
    end
end

local function SpawnSnares(inst, targets)
    if targets == nil then
        return
    end

    for i, v in ipairs(targets) do
        if v:IsValid() and v:IsNear(inst, tuning.SNARE_MAX_RANGE) then
            SpawnSnareRing(inst, v)
        end
    end
end

--------------------------------------------------------------------------
-- 效果二：螺旋骨刺（Spikes）
-- 参考原版 GenerateSpiralSpikes：阿基米德螺旋扩散，逐个延迟冒出。
--------------------------------------------------------------------------
local function SpawnSpiralSpikes(inst)
    local x, _, z = inst.Transform:GetWorldPosition()
    local spacing = tuning.SPIRAL_SPACING
    local radius = tuning.SPIRAL_START_RADIUS
    local delta_radius = tuning.SPIRAL_RADIUS_STEP
    local angle = TWOPI * math.random()
    local delta_angle_mult = (inst._kelp_spiral_reverse and -2 or 2) * PI * spacing
    inst._kelp_spiral_reverse = not inst._kelp_spiral_reverse

    local delay = 0
    local delta_delay = tuning.SPIRAL_DELAY_PER_STEP
    local num = tuning.SPIRAL_COUNT
    local map = TheWorld.Map

    for i = 1, num do
        local old_radius = radius
        radius = radius + delta_radius
        local circ = PI * (old_radius + radius)
        local delta_angle = delta_angle_mult / circ
        angle = angle + delta_angle
        local x1 = x + radius * math.cos(angle)
        local z1 = z + radius * math.sin(angle)

        if map:IsPassableAtPoint(x1, 0, z1) then
            SpawnSpikeAt(inst, x1, z1, nil, tuning.SPIKE_DURATION, delay)
        end

        delay = delay + delta_delay
    end
end

--------------------------------------------------------------------------
-- 效果三：铺蛛网（减速玩家，不影响 Boss）
-- 在海带骨刺释放前先铺一圈蛛网，限制玩家走位。
--------------------------------------------------------------------------
local function SpawnWebAt(inst, x, z)
    local web = SpawnPrefab("hermitcrab_web_ground")
    if web == nil then
        return
    end

    web.Transform:SetPosition(x, 0, z)
    web.radius = tuning.WEB_RADIUS
    web.penalty = tuning.WEB_SPEED_PENALTY
    web.duration = tuning.WEB_DURATION

    local scale = tuning.WEB_VISUAL_SCALE
    web.Transform:SetScale(scale, scale, scale)
end

local function SpawnWebField(inst)
    local x, _, z = inst.Transform:GetWorldPosition()

    -- 中心一片
    SpawnWebAt(inst, x, z)

    -- 内环
    for i = 1, tuning.WEB_INNER_COUNT do
        local theta = TWOPI * (i - 1) / tuning.WEB_INNER_COUNT
        SpawnWebAt(inst, x + tuning.WEB_INNER_RADIUS * math.cos(theta), z + tuning.WEB_INNER_RADIUS * math.sin(theta))
    end

    -- 外环
    for i = 1, tuning.WEB_OUTER_COUNT do
        local theta = TWOPI * (i - 1) / tuning.WEB_OUTER_COUNT
        SpawnWebAt(inst, x + tuning.WEB_OUTER_RADIUS * math.cos(theta), z + tuning.WEB_OUTER_RADIUS * math.sin(theta))
    end
end

--------------------------------------------------------------------------
-- 触发入口：由 SG 施法状态在动画帧调用
--------------------------------------------------------------------------
local function Spawn(inst)
    if inst._kelp_snare_released
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    inst._kelp_snare_released = true

    -- 牢笼：围绕所有在场玩家
    local targets = FindSnareTargets(inst)
    if targets ~= nil then
        SpawnSnares(inst, targets)
    end

    -- 螺旋刺：从 Boss 脚下扩散
    SpawnSpiralSpikes(inst)
end

-- 完整连招入口：先铺蛛网，再进入海带骨刺施法流程。
-- 由 50% 血量触发（OnHealthDelta -> Begin）与调试指令 c_sc 共用。
local function CastKelpSnare(inst)
    if inst._kelp_snare_triggered
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    inst._kelp_snare_triggered = true
    inst.components.combat:CancelAttack()

    -- 先铺蛛网：立即在 Boss 周围铺一圈减速网。
    SpawnWebField(inst)

    -- 再放海带骨刺：走状态机施法动画，稍后生成海带牢笼 + 螺旋。
    inst:PushEvent("hermitboss_kelp_snare")
end

local function Begin(inst)
    CastKelpSnare(inst)
end

local function OnHealthDelta(inst, data)
    if not inst._kelp_snare_triggered
        and not inst._final_phase_triggered
        and not inst._surrendering
        and inst.components.health.currenthealth > inst.components.health.minhealth
        and data ~= nil
        and data.oldpercent > tuning.PHASE_HEALTH
        and data.newpercent <= tuning.PHASE_HEALTH then
        Begin(inst)
    end
end

local function OnEncounterFinished(inst)
    inst._kelp_snare_released = nil
    inst._kelp_snare_triggered = nil
end

function KelpSnare.Attach(inst, encounter_finished_event, final_phase_started_event)
    inst.SpawnKelpSnare = Spawn
    inst.CastKelpSnare = CastKelpSnare

    inst:ListenForEvent("healthdelta", OnHealthDelta)
    inst:ListenForEvent(encounter_finished_event, OnEncounterFinished)
    -- 进入最终阶段或贝壳环阶段时，若尚未触发则不再触发。
    inst:ListenForEvent(final_phase_started_event, OnEncounterFinished)
end

return KelpSnare