require("stategraphs/commonstates")

local events =
{
    CommonHandlers.OnLocomote(true, true),

    EventHandler("doattack", function(inst, data)
        if not inst._surrendering and not inst.sg:HasStateTag("busy") then
            inst.sg:GoToState(
                "attack",
                data ~= nil and data.target or inst.components.combat.target
            )
        end
    end),

    EventHandler("attacked", function(inst)
        if not inst._surrendering and not inst.sg:HasStateTag("busy") then
            inst.sg:GoToState("hit")
        end
    end),

    EventHandler("hermitboss_surrender", function(inst)
        if not inst.sg:HasStateTag("surrender") then
            inst.sg:GoToState("surrender")
        end
    end),
}

local states =
{
    State
    {
        name = "idle",
        tags = { "idle", "canrotate" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.AnimState:PlayAnimation("idle_loop", true)
        end,
    },

    State
    {
        name = "attack",
        tags = { "attack", "busy" },

        onenter = function(inst, target)
            inst.components.locomotor:StopMoving()
            inst.components.combat:StartAttack()
            inst.sg.statemem.target = target
            inst.AnimState:PlayAnimation("give")
        end,

        timeline =
        {
            TimeEvent(10 * FRAMES, function(inst)
                inst.components.combat:DoAttack(inst.sg.statemem.target)
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    },

    State
    {
        name = "hit",
        tags = { "hit", "busy" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.AnimState:PlayAnimation("hit")
            inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/hurt")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    },

    State
    {
        name = "surrender",
        tags = { "busy", "surrender", "noattack" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("hit")
            inst.sg:SetTimeout(1)
        end,

        events =
        {
            EventHandler("animover", function(inst)
                inst:FinishEncounter(true)
            end),
        },

        ontimeout = function(inst)
            inst:FinishEncounter(true)
        end,
    },
}

CommonStates.AddWalkStates(states, nil,
{
    startwalk = "walk_pre",
    walk = "walk_loop",
    stopwalk = "walk_pst",
})

CommonStates.AddRunStates(states, nil,
{
    startrun = "run_pre",
    run = "run_loop",
    stoprun = "run_pst",
})

return StateGraph("hermitcrab_boss", states, events, "idle")
