-- ============================================================================
-- 海带骨刺技能·牢笼：血量降至 50% 时触发。
-- 用"竖立的海带"（海带植株 bullkelp 的竖立形态）模拟远古织影者的
-- Snare 骨刺牢笼：围绕每个玩家一圈竖立海带，形成牢笼并造成接触伤害。
-- 视觉实体复用 hermitcrab_kelp_spike（海带植株竖立形态）。
-- 与 kelp_spiral（阿基米德螺旋）拆分为两个独立技能：各自独立注册阶段、事件与
-- 调参，但共用一次施法动画，在同一帧释放（互斥由 phase_scheduler 统一维护）。
-- ============================================================================

local events = require("hermitcrab_boss/events")
local kelp_spike = require("hermitcrab_boss/skills/kelp_spike")
local phase_scheduler = require("hermitcrab_boss/phase_scheduler")
local tuning = require("hermitcrab_boss/tuning").KELP_SNARE

local KelpSnare =
{
    PREFABS = kelp_spike.PREFABS,
}

-- 玩家目标过滤
local PLAYER_MUST_TAGS = { "player" }
local PLAYER_CANT_TAGS = { "playerghost", "INLIMBO" }

--------------------------------------------------------------------------
-- 骨刺牢笼（Snare）
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

            kelp_spike.SpawnSpikeAt(inst, x1, z1, variation, nil, delay)
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
-- 触发入口：由 SG 施法状态在动画帧调用
--------------------------------------------------------------------------
local function Spawn(inst)
    -- 未触发本技能（如只触发了螺旋）时不生成；_released 保证同帧/超时兜底不重复生成。
    if inst._kelp_snare_released
        or not phase_scheduler.IsTriggered(inst, events.KELP_SNARE)
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
end

-- 完整连招入口：由 phase_scheduler 在 50% 血量跨越时触发，也可由调试指令 c_sc 调用。
-- 互斥标志统一存放在 inst._phase_triggered[events.KELP_SNARE]。
local function Trigger(inst)
    if phase_scheduler.IsTriggered(inst, events.KELP_SNARE)
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    phase_scheduler.MarkTriggered(inst, events.KELP_SNARE)
    inst.components.combat:CancelAttack()
    inst:PushEvent(events.KELP_SNARE)
end

-- 清理本模块的临时状态。战斗结束 / 最终阶段开始时被调用，
-- 防止残留标志影响（本 Boss 实例会被移除，这里主要起防御作用）。
local function OnEncounterFinished(inst)
    inst._kelp_snare_released = nil
end

function KelpSnare.Attach(inst)
    inst.SpawnKelpSnare = Spawn
    inst.CastKelpSnare = Trigger
    inst.TriggerKelpSnare = Trigger

    inst:ListenForEvent(events.ENCOUNTER_FINISHED, OnEncounterFinished)
    inst:ListenForEvent(events.FINAL_PHASE_STARTED, OnEncounterFinished)
end

return KelpSnare
