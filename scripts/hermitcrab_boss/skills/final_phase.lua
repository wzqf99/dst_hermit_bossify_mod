local house_defense = require("hermitcrab_boss/house_defense")
local tuning = require("hermitcrab_boss/tuning").FINAL_PHASE

local FinalPhase =
{
    STARTED_EVENT = "hermitboss_final_phase_started",
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

local function Begin(inst)
    if inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    inst._final_phase_triggered = true
    inst._final_state = FinalPhase.STATE.ENTER_FINAL_PHASE
    inst.components.health:SetInvincible(true)
    inst.components.combat:SetTarget(nil)
    inst.components.combat:CancelAttack()
    inst.components.locomotor:Stop()
    inst:StopBrain("hermitboss_final_phase")
    inst:PushEvent(FinalPhase.STARTED_EVENT)
    inst:PushEvent("hermitboss_enter_final_phase")
end

local function OnHealthDelta(inst, data)
    if not inst._final_phase_triggered
        and not inst._surrendering
        and data ~= nil
        and data.oldpercent > tuning.PHASE_HEALTH
        and data.newpercent <= tuning.PHASE_HEALTH then
        Begin(inst)
    end
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

function FinalPhase.Attach(inst, encounter_finishing_event)
    inst._final_state = FinalPhase.STATE.NORMAL
    inst.EnterHouseDefense = EnterHouseDefense

    inst:ListenForEvent("healthdelta", OnHealthDelta)
    inst:ListenForEvent(encounter_finishing_event, OnEncounterFinishing)
    inst:ListenForEvent("onremove", OnRemoveEntity)
end

return FinalPhase
