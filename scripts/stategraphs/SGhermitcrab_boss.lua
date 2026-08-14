-- ============================================================================
-- Boss 动画状态机（Stategraph）
-- 状态流程：
--   idle ←→ attack / hit / walk / run
--   idle → surrender → FinishEncounter(true)
-- 攻击使用标准持武器动作，75% 血量时使用三叉戟拨弦动作，
-- 受伤和投降使用 "hit" 动画。
-- ============================================================================

require("stategraphs/commonstates")

local event_names = require("hermitcrab_boss/events")

local events =
{
    -- 移动事件（由 locomotor 组件驱动）
    CommonHandlers.OnLocomote(true, true),

    -- 攻击事件：进入 attack 状态，记录目标
    EventHandler("doattack", function(inst, data)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst.sg:HasStateTag("busy") then
            inst.sg:GoToState(
                "attack",
                data ~= nil and data.target or inst.components.combat.target
            )
        end
    end),

    -- 受伤事件：进入 hit 状态
    EventHandler("attacked", function(inst)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst.sg:HasStateTag("busy") then
            inst.sg:GoToState("hit")
        end
    end),

    -- 投降事件：由 BeginSurrender 推送，进入投降状态
    EventHandler(event_names.SURRENDER, function(inst)
        if not inst.sg:HasStateTag("surrender") then
            inst.sg:GoToState("surrender")
        end
    end),

    -- 90% 血量阶段：用竖立的海带模拟骨刺牢笼 + 螺旋骨刺。
    EventHandler(event_names.KELP_SNARE, function(inst)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst._encounter_resolved then
            inst.sg:GoToState("kelp_snare")
        end
    end),

    -- 75% 血量阶段：强制打断当前动作并使用三叉戟召出贝壳堆。
    EventHandler(event_names.SHELL_PHASE, function(inst)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst._encounter_resolved then
            inst.sg:GoToState("trident_cast")
        end
    end),

    -- 50% 血量阶段：使用星杖动作召唤三只蟹卫。
    EventHandler(event_names.GUARD_SUMMON, function(inst)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst._encounter_resolved then
            inst.sg:GoToState("staff_cast")
        end
    end),

    -- 30% 最终阶段：播放原版搬家时的拍手动画，再由房屋接管战斗。
    EventHandler(event_names.ENTER_FINAL_PHASE, function(inst)
        if not inst._surrendering and not inst._encounter_resolved then
            inst.sg:GoToState("enter_final_phase")
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
    -- 攻击（手持三叉戟的标准武器攻击）
    -- ============================
    State
    {
        name = "attack",
        tags = { "attack", "busy" },

        onenter = function(inst, target)
            inst.components.locomotor:StopMoving()
            inst.components.combat:StartAttack()
            inst.sg.statemem.target = target

            inst.AnimState:PlayAnimation("atk_pre")
            inst.AnimState:PushAnimation("atk", false)
        end,

        timeline =
        {
            TimeEvent(8 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/wilson/attack_weapon")
                inst.components.combat:DoAttack(inst.sg.statemem.target)
            end),
        },

        events =
        {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    -- ============================
    -- 90% 血量：海带骨刺（骨刺牢笼 + 螺旋骨刺）
    -- 复用星杖施法动画作为抬手动作，在帧上释放海带刺。
    -- ============================
    State
    {
        name = "kelp_snare",
        tags = { "busy", "noattack", "playing" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.components.combat:CancelAttack()
            inst.components.health:SetInvincible(true)

            inst.AnimState:OverrideSymbol("swap_object", "swap_trident", "swap_trident")
            inst.AnimState:OverrideSymbol("swap_trident", "swap_trident", "swap_trident")
            inst.AnimState:Show("ARM_carry")
            inst.AnimState:Hide("ARM_normal")
            inst.AnimState:PlayAnimation("staff_pre")
            inst.AnimState:PushAnimation("staff", false)

            -- 动画资源异常时也能自动退出，不会永久卡在施法中。
            inst.sg:SetTimeout(2.25)
        end,

        timeline =
        {
            TimeEvent(8 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/common/staffteleport")
            end),
            TimeEvent(14 * FRAMES, function(inst)
                inst:SpawnKelpSnare()
            end),
        },

        events =
        {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        ontimeout = function(inst)
            inst:SpawnKelpSnare()
            inst.sg:GoToState("idle")
        end,

        onexit = function(inst)
            if not inst._surrendering
                and not inst._final_phase_triggered
                and not inst._encounter_resolved then
                inst.components.health:SetInvincible(false)
            end
        end,
    },

    -- ============================
    -- 75% 血量：三叉戟喷水柱召唤
    -- 使用原版三叉戟的 strum_pre / strum 动画和触发帧。
    -- ============================
    State
    {
        name = "trident_cast",
        tags = { "busy", "noattack", "playing" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.components.combat:CancelAttack()
            inst.components.health:SetInvincible(true)

            inst.AnimState:OverrideSymbol("swap_object", "swap_trident", "swap_trident")
            inst.AnimState:OverrideSymbol("swap_trident", "swap_trident", "swap_trident")
            inst.AnimState:Show("ARM_carry")
            inst.AnimState:Hide("ARM_normal")
            inst.AnimState:PlayAnimation("strum_pre")
            inst.AnimState:PushAnimation("strum", false)

            -- 动画资源异常时也能自动退出，不会永久卡在阶段转换中。
            inst.sg:SetTimeout(2.25)
        end,

        timeline =
        {
            TimeEvent(23 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("hookline_2/characters/trident_attack")
            end),
            TimeEvent(28 * FRAMES, function(inst)
                inst:SpawnShellRing()
            end),
        },

        events =
        {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        ontimeout = function(inst)
            inst:SpawnShellRing()
            inst.sg:GoToState("idle")
        end,

        onexit = function(inst)
            if not inst._surrendering
                and not inst._final_phase_triggered
                and not inst._encounter_resolved then
                inst.components.health:SetInvincible(false)
            end
        end,
    },

    -- ============================
    -- 50% 血量：星杖动作召唤蟹卫
    -- 复用原版星杖的 staff_pre / staff 施法动画。
    -- ============================
    State
    {
        name = "staff_cast",
        tags = { "busy", "noattack", "playing" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.components.combat:CancelAttack()
            inst.components.health:SetInvincible(true)

            inst.AnimState:OverrideSymbol("swap_object", "swap_trident", "swap_trident")
            inst.AnimState:OverrideSymbol("swap_trident", "swap_trident", "swap_trident")
            inst.AnimState:Show("ARM_carry")
            inst.AnimState:Hide("ARM_normal")
            inst.AnimState:PlayAnimation("staff_pre")
            inst.AnimState:PushAnimation("staff", false)

            -- 动画资源异常时也能自动退出，不会永久卡在施法中。
            inst.sg:SetTimeout(2.25)
        end,

        timeline =
        {
            TimeEvent(8 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/common/staffteleport")
            end),
            TimeEvent(14 * FRAMES, function(inst)
                inst:SpawnGuards()
            end),
        },

        events =
        {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        ontimeout = function(inst)
            inst:SpawnGuards()
            inst.sg:GoToState("idle")
        end,

        onexit = function(inst)
            if not inst._surrendering
                and not inst._final_phase_triggered
                and not inst._encounter_resolved then
                inst.components.health:SetInvincible(false)
            end
        end,
    },

    -- ============================
    -- 受击
    -- ============================
    State
    {
        name = "enter_final_phase",
        tags = { "busy", "noattack", "playing", "finalphase" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.components.combat:CancelAttack()
            inst.components.health:SetInvincible(true)

            -- 原版搬家水遁实际使用 idle_clack 动画配合 hermitcrab_fx_small。
            inst.AnimState:PlayAnimation("idle_clack_pre")
            inst.AnimState:PushAnimation("idle_clack_loop", false)
            inst.sg:SetTimeout(2.5)
        end,

        timeline =
        {
            TimeEvent(13 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/clap")
            end),
            TimeEvent(29 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/clap")
            end),
        },

        events =
        {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst:EnterHouseDefense()
                end
            end),
        },

        ontimeout = function(inst)
            inst:EnterHouseDefense()
        end,
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
