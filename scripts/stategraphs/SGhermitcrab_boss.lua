-- ============================================================================
-- Boss 动画状态机（Stategraph）
-- 状态流程：
--   intro → idle ←→ attack / hit / walk / run
--   idle → surrender → FinishEncounter(true)
-- 开战衔接使用原版 idle_clack 拍手钳动作（pre → loop → pst），
-- 结束衔接使用原版被打晕的 idle_groggy 待机（pre → loop）。
-- ============================================================================

require("stategraphs/commonstates")

local event_names = require("hermitcrab_boss/events")

local events =
{
    -- 移动事件（由 locomotor 组件驱动）
    CommonHandlers.OnLocomote(true, true),

    -- 攻击事件：一阶段进入 bottle_attack（远程投瓶），75% 后进入 attack（近战）。
    EventHandler("doattack", function(inst, data)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst.sg:HasStateTag("busy") then
            inst.sg:GoToState(
                inst._bottle_mode and "bottle_attack" or "attack",
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

    -- 50% 血量阶段：海带骨刺连招（骨刺牢笼 + 螺旋骨刺，两个独立技能共用一次施法）。
    EventHandler(event_names.KELP_SNARE, function(inst)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst._encounter_resolved then
            inst.sg:GoToState("kelp_cast")
        end
    end),
    EventHandler(event_names.KELP_SPIRAL, function(inst)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst._encounter_resolved then
            inst.sg:GoToState("kelp_cast")
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

    -- 贝壳全灭后的重新召唤：复用 trident_cast 施法动画，但不推 SHELL_PHASE，
    -- 避免 fissure 模块把裂隙月相等级降级。
    EventHandler(event_names.SHELL_RESUMMON, function(inst)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst._encounter_resolved then
            inst.sg:GoToState("trident_cast")
        end
    end),

    -- 贝壳聚拢轰炸：贝壳环后每 15 秒循环，进入施法状态（贝壳头顶蓄力后砸落）。
    EventHandler(event_names.SHELL_BOMBARD, function(inst)
        if not inst._surrendering
            and not inst._final_phase_triggered
            and not inst._encounter_resolved then
            inst.sg:GoToState("shell_bombard_cast")
        end
    end),

    -- 90% 血量阶段：使用星杖动作召唤三只蟹卫（从裂隙处钻出）。
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
    -- 开战仪式（Boss 生成后进入的第一个状态）
    -- 使用原版 idle_clack 拍手钳动作作为开战衔接：
    -- pre → loop（循环拍手，展示两轮）→ intro_pst → idle
    -- ============================
    State
    {
        name = "intro",
        tags = { "busy", "noattack", "playing" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.components.combat:CancelAttack()

            inst.AnimState:PlayAnimation("idle_clack_pre")
            inst.AnimState:PushAnimation("idle_clack_loop", true)

            -- 动画资源异常时也能自动退出，不会卡在开战动画里
            inst.sg:SetTimeout(5)
        end,

        timeline =
        {
            -- 每次拍钳的节拍音效（idle_clack_loop 为 31 帧一轮，每轮拍两下）
            TimeEvent(13 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/clap")
            end),
            TimeEvent(29 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/clap")
            end),
            TimeEvent((13 + 31) * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/clap")
            end),
            TimeEvent((29 + 31) * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/clap")
            end),
        },

        events =
        {
            -- pre 播完进入 loop 循环拍手后，展示两轮再进入收尾
            EventHandler("animover", function(inst)
                if not inst.sg.statemem.clack_loop_started then
                    inst.sg.statemem.clack_loop_started = true
                    inst.sg:SetTimeout(2 * (31 * FRAMES))
                end
            end),
        },

        ontimeout = function(inst)
            inst.sg:GoToState("intro_pst")
        end,
    },

    -- ============================
    -- 开战仪式收尾（clack 结束动作，回到待机）
    -- ============================
    State
    {
        name = "intro_pst",
        tags = { "busy", "noattack", "playing" },

        onenter = function(inst)
            inst.AnimState:PlayAnimation("idle_clack_pst")
            inst.sg:SetTimeout(2)
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        ontimeout = function(inst)
            inst.sg:GoToState("idle")
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
    -- 一阶段远程投瓶：复用原版隐士 throw 动画（hermitcrab_build 自带），
    -- 手持漂流瓶，第 7 帧向玩家脚下抛出一个瓶子（落地爆炸由 bottle_toss 处理）。
    -- ============================
    State
    {
        name = "bottle_attack",
        tags = { "attack", "busy" },

        onenter = function(inst, target)
            inst.components.locomotor:StopMoving()
            inst.components.combat:StartAttack()
            inst.sg.statemem.target = target

            inst.AnimState:OverrideSymbol("swap_object", "swap_bottle", "swap_bottle")
            inst.AnimState:Show("ARM_carry")
            inst.AnimState:Hide("ARM_normal")
            inst.AnimState:PlayAnimation("throw")
            inst.sg:SetTimeout(1.5)
        end,

        timeline =
        {
            -- 原版隐士 throw 的投掷帧在第 7 帧。
            TimeEvent(7 * FRAMES, function(inst)
                inst:ThrowBottleAt(inst.sg.statemem.target)
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        ontimeout = function(inst)
            inst.sg:GoToState("idle")
        end,
    },

    -- ============================
    -- 50% 血量：海带骨刺连招（牢笼 + 螺旋）
    -- 两个独立技能（kelp_snare / kelp_spiral）共用一次星杖施法动画，
    -- 在帧上同时释放；各技能内部按自身触发状态决定是否生成。
    -- ============================
    State
    {
        name = "kelp_cast",
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
                inst:SpawnKelpSpiral()
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
            inst:SpawnKelpSpiral()
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
    -- 贝壳聚拢轰炸：贝壳环后每 15 秒循环。
    -- 施法前摇复用三叉戟 strum 动画；实际聚拢/旋转/投掷由 shell_bombard 模块
    -- 在动画帧启动，贝壳实体在此期间被技能接管（脱离原环绕轨道）。
    -- ============================
    State
    {
        name = "shell_bombard_cast",
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

            -- 动画资源异常时也能自动退出，不会永久卡在施法中。
            inst.sg:SetTimeout(2.25)
        end,

        timeline =
        {
            TimeEvent(23 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("hookline_2/characters/trident_attack")
            end),
            TimeEvent(28 * FRAMES, function(inst)
                inst:CastShellBombard()
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
            inst:CastShellBombard()
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

            -- 一阶段手持漂流瓶召唤蟹卫：用瓶子做星杖施法动作。
            inst.AnimState:OverrideSymbol("swap_object", "swap_bottle", "swap_bottle")
            inst.AnimState:OverrideSymbol("swap_trident", "swap_bottle", "swap_bottle")
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
    -- 结束衔接：使用原版被打晕的待机动作（idle_groggy_pre → idle_groggy 循环），
    -- 展示一段眩晕脱力后再结束战斗。
    -- noattack 标签：防止在投降动画中触发攻击
    -- ============================
    State
    {
        name = "surrender",
        tags = { "busy", "surrender", "noattack" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.components.combat:CancelAttack()

            inst.AnimState:PlayAnimation("idle_groggy_pre")
            inst.AnimState:PushAnimation("idle_groggy", true)

            -- 兜底超时：动画资源异常时也能结束战斗
            inst.sg:SetTimeout(4)
        end,

        events =
        {
            -- pre 播完进入 groggy 眩晕循环后，再展示一会儿再结束
            EventHandler("animover", function(inst)
                inst.sg:SetTimeout(1.5)
            end),
        },

        -- 超时兜底 → 也按胜利结束
        ontimeout = function(inst)
            inst._victory_animation_finished = true
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

return StateGraph("hermitcrab_boss", states, events, "intro")
