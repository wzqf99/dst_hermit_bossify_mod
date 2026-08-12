-- ============================================================================
-- Boss 动画状态机（Stategraph）
-- 状态流程：
--   idle ←→ attack / hit / walk / run
--   idle → surrender → FinishEncounter(true)
-- 攻击动画使用 "give"（寄居蟹"给予"动作作为攻击），
-- 受伤和投降使用 "hit" 动画
-- ============================================================================

require("stategraphs/commonstates")

local events =
{
    -- 移动事件（由 locomotor 组件驱动）
    CommonHandlers.OnLocomote(true, true),

    -- 攻击事件：进入 attack 状态，记录目标
    EventHandler("doattack", function(inst, data)
        if not inst._surrendering and not inst.sg:HasStateTag("busy") then
            inst.sg:GoToState(
                "attack",
                data ~= nil and data.target or inst.components.combat.target
            )
        end
    end),

    -- 受伤事件：进入 hit 状态
    EventHandler("attacked", function(inst)
        if not inst._surrendering and not inst.sg:HasStateTag("busy") then
            inst.sg:GoToState("hit")
        end
    end),

    -- 投降事件：由 BeginSurrender 推送，进入投降状态
    EventHandler("hermitboss_surrender", function(inst)
        if not inst.sg:HasStateTag("surrender") then
            inst.sg:GoToState("surrender")
        end
    end),
}

local states =
{
    -- ============================
    -- 待机
    -- ============================
    State
    {
        name = "idle",
        tags = { "idle", "canrotate" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.AnimState:PlayAnimation("idle_loop", true)
        end,
    },

    -- ============================
    -- 攻击（使用寄居蟹"给予"动画）
    -- ============================
    State
    {
        name = "attack",
        tags = { "attack", "busy" },

        onenter = function(inst, target)
            inst.components.locomotor:StopMoving()
            inst.components.combat:StartAttack()
            inst.sg.statemem.target = target

            -- 使用"give"动画模拟攻击，给予→攻击的语义转换
            inst.AnimState:PlayAnimation("give")
        end,

        timeline =
        {
            -- 动画第 10 帧时造成伤害
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

    -- ============================
    -- 受击
    -- ============================
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

    -- ============================
    -- 投降（打到 1 血时）
    -- noattack 标签：防止在投降动画中触发攻击
    -- ============================
    State
    {
        name = "surrender",
        tags = { "busy", "surrender", "noattack" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("hit")

            -- 1 秒兜底超时：防止动画卡住导致战斗无法结束
            inst.sg:SetTimeout(1)
        end,

        events =
        {
            -- 动画播放完毕 → 胜利结束
            EventHandler("animover", function(inst)
                inst:FinishEncounter(true)
            end),
        },

        -- 超时兜底 → 也按胜利结束
        ontimeout = function(inst)
            inst:FinishEncounter(true)
        end,
    },
}

-- 添加行走状态（使用寄居蟹行走动画）
CommonStates.AddWalkStates(states, nil,
{
    startwalk = "walk_pre",
    walk = "walk_loop",
    stopwalk = "walk_pst",
})

-- 添加奔跑状态
CommonStates.AddRunStates(states, nil,
{
    startrun = "run_pre",
    run = "run_loop",
    stoprun = "run_pst",
})

return StateGraph("hermitcrab_boss", states, events, "idle")
