-- 蟹卫召唤技能：血量降至 50% 时，使用星杖动作召唤三只蟹卫（复用原版 crabking_mob）。
local tuning = require("hermitcrab_boss/tuning").GUARD_SUMMON

local GuardSummon =
{
    PREFABS =
    {
        "crabking_mob",
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
    if inst._summoned_guards == nil then
        return
    end

    for _, guard in ipairs(inst._summoned_guards) do
        if guard:IsValid() then
            guard:Remove()
        end
    end
    inst._summoned_guards = nil
end

local function OnEncounterFinished(inst)
    RemoveGuards(inst)
    inst._guard_summon_released = nil
    inst._guard_summon_triggered = nil
end

local function Begin(inst)
    if inst._guard_summon_triggered
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    inst._guard_summon_triggered = true
    inst.components.combat:CancelAttack()
    inst:PushEvent("hermitboss_guard_summon")
end

local function OnHealthDelta(inst, data)
    if not inst._guard_summon_triggered
        and not inst._final_phase_triggered
        and not inst._surrendering
        and inst.components.health.currenthealth > inst.components.health.minhealth
        and data ~= nil
        and data.oldpercent > tuning.PHASE_HEALTH
        and data.newpercent <= tuning.PHASE_HEALTH then
        Begin(inst)
    end
end

function GuardSummon.Attach(inst, encounter_finished_event, final_phase_started_event)
    inst.SpawnGuards = SpawnGuards

    inst:ListenForEvent("healthdelta", OnHealthDelta)
    inst:ListenForEvent(encounter_finished_event, OnEncounterFinished)
    inst:ListenForEvent(final_phase_started_event, RemoveGuards)
end

return GuardSummon
