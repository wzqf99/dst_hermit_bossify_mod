-- ============================================================================
-- 海带骨刺技能·螺旋：血量降至 50% 时触发。
-- 用"竖立的海带"（海带植株 bullkelp 的竖立形态）模拟远古织影者的
-- Spikes 螺旋骨刺：从 Boss 脚下以阿基米德螺旋扩散，逐个延迟冒出。
-- 释放前先在 Boss 脚下铺一片蛛网减速玩家（与螺旋同为 Boss 脚下特效）。
-- 视觉实体复用 hermitcrab_kelp_spike / hermitcrab_web_ground。
-- 与 kelp_snare（骨刺牢笼）拆分为两个独立技能：各自独立注册阶段、事件与
-- 调参，但共用一次施法动画，在同一帧释放（互斥由 phase_scheduler 统一维护）。
-- ============================================================================

local events = require("hermitcrab_boss/events")
local kelp_spike = require("hermitcrab_boss/skills/kelp_spike")
local phase_scheduler = require("hermitcrab_boss/phase_scheduler")
local tuning = require("hermitcrab_boss/tuning").KELP_SPIRAL

local KelpSpiral =
{
    PREFABS =
    {
        "hermitcrab_kelp_spike",
        "hermitcrab_web_ground",
    },
}

--------------------------------------------------------------------------
-- 螺旋骨刺（Spikes）
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
            kelp_spike.SpawnSpikeAt(inst, x1, z1, nil, nil, delay)
        end

        delay = delay + delta_delay
    end
end

--------------------------------------------------------------------------
-- 铺蛛网（减速玩家，不影响 Boss）
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

    -- 只在 Boss 脚下铺一片蛛网。
    SpawnWebAt(inst, x, z)
end

--------------------------------------------------------------------------
-- 触发入口：由 SG 施法状态在动画帧调用
--------------------------------------------------------------------------
local function Spawn(inst)
    -- 未触发本技能（如只触发了牢笼）时不生成；_released 保证同帧/超时兜底不重复生成。
    if inst._kelp_spiral_released
        or not phase_scheduler.IsTriggered(inst, events.KELP_SPIRAL)
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    inst._kelp_spiral_released = true

    -- 螺旋刺：从 Boss 脚下扩散
    SpawnSpiralSpikes(inst)
end

-- 完整连招入口：先铺蛛网，再进入螺旋施法流程。
-- 由 phase_scheduler 在 50% 血量跨越时触发，也可由调试指令 c_sc 调用。
-- 互斥标志统一存放在 inst._phase_triggered[events.KELP_SPIRAL]。
local function Trigger(inst)
    if phase_scheduler.IsTriggered(inst, events.KELP_SPIRAL)
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    phase_scheduler.MarkTriggered(inst, events.KELP_SPIRAL)
    inst.components.combat:CancelAttack()

    -- 先铺蛛网：立即在 Boss 脚下铺一圈减速网。
    SpawnWebField(inst)

    -- 再放螺旋骨刺：走状态机施法动画，稍后生成阿基米德螺旋。
    inst:PushEvent(events.KELP_SPIRAL)
end

-- 清理本模块的临时状态。战斗结束 / 最终阶段开始时被调用，
-- 防止残留标志影响（本 Boss 实例会被移除，这里主要起防御作用）。
local function OnEncounterFinished(inst)
    inst._kelp_spiral_released = nil
end

function KelpSpiral.Attach(inst)
    inst.SpawnKelpSpiral = Spawn
    inst.CastKelpSpiral = Trigger
    inst.TriggerKelpSpiral = Trigger

    inst:ListenForEvent(events.ENCOUNTER_FINISHED, OnEncounterFinished)
    inst:ListenForEvent(events.FINAL_PHASE_STARTED, OnEncounterFinished)
end

return KelpSpiral
