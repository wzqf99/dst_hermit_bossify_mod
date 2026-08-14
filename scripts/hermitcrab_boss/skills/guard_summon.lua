-- 蟹卫召唤技能：血量降至 90% 时，使用星杖动作召唤三只蟹卫（复用原版 crabking_mob）。
local events = require("hermitcrab_boss/events")
local phase_scheduler = require("hermitcrab_boss/phase_scheduler")
local util = require("hermitcrab_boss/util")
local tuning = require("hermitcrab_boss/tuning").GUARD_SUMMON

local GuardSummon =
{
    PREFABS =
    {
        "crabking_mob",
        "hermitcrab_fx_small",
    },
}

local function IsSpawnableAt(x, z)
    return TheWorld.Map:IsPassableAtPoint(x, 0, z)
end

-- 在 Boss 周围分扇区寻找可通过点，保证三只蟹卫分散而非挤在一起。
local function FindSpawnPoints(inst)
    local x, _, z = inst.Transform:GetWorldPosition()
    local points = {}
    local sector = TWOPI / tuning.COUNT
    local start_angle = math.random() * TWOPI

    for index = 1, tuning.COUNT do
        local sector_angle = start_angle + (index - 1) * sector
        for _ = 1, tuning.SPAWN_ATTEMPTS do
            local angle = sector_angle + (math.random() - 0.5) * sector * 0.8
            local radius = tuning.SPAWN_MIN_RADIUS
                + math.random() * (tuning.SPAWN_MAX_RADIUS - tuning.SPAWN_MIN_RADIUS)
            local px = x + radius * math.cos(angle)
            local pz = z - radius * math.sin(angle)
            if IsSpawnableAt(px, pz) then
                table.insert(points, Vector3(px, 0, pz))
                break
            end
        end
    end

    -- 分扇区不足时，不分扇区随机兜底。
    local fallback = 0
    while #points < tuning.COUNT and fallback < tuning.COUNT * 8 do
        local angle = math.random() * TWOPI
        local radius = math.random() * tuning.SPAWN_MAX_RADIUS
        local px = x + radius * math.cos(angle)
        local pz = z - radius * math.sin(angle)
        if IsSpawnableAt(px, pz) then
            table.insert(points, Vector3(px, 0, pz))
        end
        fallback = fallback + 1
    end

    return points
end

local function SpawnGuards(inst)
    if inst._guard_summon_released
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    inst._guard_summon_released = true
    inst._summoned_guards = inst._summoned_guards or {}

    local boss_target = inst.components.combat ~= nil
        and inst.components.combat.target
        or nil

    for _, point in ipairs(FindSpawnPoints(inst)) do
        -- 水遁特效：蟹卫从水遁中钻出（复用原版寄居蟹搬家水遁特效）
        local fx = SpawnPrefab("hermitcrab_fx_small")
        if fx ~= nil then
            fx.Transform:SetPosition(point:Get())
        end

        local guard = SpawnPrefab("crabking_mob")
        if guard ~= nil then
            guard.Transform:SetPosition(point:Get())
            -- 让蟹卫立即追击 Boss 当前的目标（通常是触发战斗的玩家）
            if boss_target ~= nil and boss_target:IsValid() then
                guard.components.combat:SetTarget(boss_target)
            end
            table.insert(inst._summoned_guards, guard)
        end
    end
end

local function RemoveGuards(inst)
    util.RemoveEntityList(inst, "_summoned_guards")
end

local function OnEncounterFinished(inst)
    RemoveGuards(inst)
    inst._guard_summon_released = nil
end

-- 由 phase_scheduler 在 90% 血量跨越时触发。
local function Trigger(inst)
    if phase_scheduler.IsTriggered(inst, events.GUARD_SUMMON)
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    phase_scheduler.MarkTriggered(inst, events.GUARD_SUMMON)
    inst.components.combat:CancelAttack()
    -- 打开岛上堵住裂缝的逻辑由 hermitcrab_boss/fissure 模块监听本事件处理。
    inst:PushEvent(events.GUARD_SUMMON)
end

function GuardSummon.Attach(inst)
    inst.SpawnGuards = SpawnGuards
    inst.TriggerGuardSummon = Trigger

    inst:ListenForEvent(events.ENCOUNTER_FINISHED, OnEncounterFinished)
    inst:ListenForEvent(events.FINAL_PHASE_STARTED, RemoveGuards)
end

return GuardSummon
