local events = require("hermitcrab_boss/events")
local house_defense = require("hermitcrab_boss/house_defense")
local phase_scheduler = require("hermitcrab_boss/phase_scheduler")
local tuning = require("hermitcrab_boss/tuning").FINAL_PHASE

local FinalPhase =
{
    PREFABS =
    {
        "hermitcrab_fx_small",
    },
}

for _, prefab in ipairs(house_defense.PREFABS) do
    table.insert(FinalPhase.PREFABS, prefab)
end

FinalPhase.STATE =
{
    NORMAL = "NORMAL",
    ENTER_FINAL_PHASE = "ENTER_FINAL_PHASE",
    HOUSE_DEFENSE = house_defense.ACTIVE_STATE,
}

local function EnterHouseDefense(inst)
    if inst._final_state ~= FinalPhase.STATE.ENTER_FINAL_PHASE
        or inst._encounter_resolved then
        return
    end

    local fx = SpawnPrefab("hermitcrab_fx_small")
    if fx ~= nil then
        fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    end
    house_defense.Activate(inst)
end

-- 由 phase_scheduler 在 30% 血量跨越时触发。
-- 这是最后一个阶段，一旦触发其他阶段技能都会停止（_final_phase_triggered 置位）。
local function Trigger(inst)
    if phase_scheduler.IsTriggered(inst, events.FINAL_PHASE_STARTED)
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    phase_scheduler.MarkTriggered(inst, events.FINAL_PHASE_STARTED)
    inst._final_phase_triggered = true
    inst._final_state = FinalPhase.STATE.ENTER_FINAL_PHASE
    inst.components.health:SetInvincible(true)
    inst.components.combat:SetTarget(nil)
    inst.components.combat:CancelAttack()
    inst.components.locomotor:Stop()
    inst:StopBrain("hermitboss_final_phase")
    inst:PushEvent(events.FINAL_PHASE_STARTED)
    inst:PushEvent(events.ENTER_FINAL_PHASE)
end

local function OnEncounterFinishing(inst)
    house_defense.Cleanup(inst, true)
end

local function OnRemoveEntity(inst)
    house_defense.Cleanup(inst, true)
end

function FinalPhase.RegisterHousePostInits(add_prefab_post_init)
    house_defense.RegisterHousePostInits(add_prefab_post_init)
end

function FinalPhase.Attach(inst)
    inst._final_state = FinalPhase.STATE.NORMAL
    inst.TriggerFinalPhase = Trigger
    inst.EnterHouseDefense = EnterHouseDefense

    inst:ListenForEvent(events.ENCOUNTER_FINISHING, OnEncounterFinishing)
    inst:ListenForEvent("onremove", OnRemoveEntity)
end

return FinalPhase
