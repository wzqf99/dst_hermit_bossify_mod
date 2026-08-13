-- ============================================================================
-- Boss 动画状态机（Stategraph）
-- 状态流程：
--   idle ←→ attack / hit / walk / run
--   idle → surrender → FinishEncounter(true)
-- 攻击使用标准持武器动作，75% 血量时使用三叉戟拨弦动作，
-- 50% 血量时使用星杖施法动作召唤蟹卫，
-- 30% 血量时走入小屋化身炮塔（turret_walk → turret_enter → turret_active），
-- 受伤和投降使用 "hit" 动画。
-- ============================================================================

require("stategraphs/commonstates")

local house_turret_tuning = require("hermitcrab_boss/tuning").HOUSE_TURRET

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

    -- 75% 血量阶段：强制打断当前动作并使用三叉戟召出贝壳堆。
    EventHandler("hermitboss_shell_phase", function(inst)
        if not inst._surrendering and not inst._encounter_resolved then
            inst.sg:GoToState("trident_cast")
        end
    end),

    -- 50% 血量阶段：使用星杖动作召唤三只蟹卫。
    EventHandler("hermitboss_guard_summon", function(inst)
        if not inst._surrendering and not inst._encounter_resolved then
            inst.sg:GoToState("staff_cast")
        end
    end),

    -- 30% 血量阶段：走入小屋化身炮塔。
    EventHandler("hermitboss_house_turret", function(inst)
        if not inst._surrendering and not inst._encounter_resolved then
            inst.sg:GoToState("turret_walk")
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
            if not inst._surrendering and not inst._encounter_resolved then
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
            if not inst._surrendering and not inst._encounter_resolved then
                inst.components.health:SetInvincible(false)
            end
        end,
    },

    -- ============================
    -- 30% 血量：走向小屋
    -- 距小屋 ≤40 用原版行走动画走过去，更远直接传送到门口；
    -- 走到门口后由 house_turret 模块推送 turret_enter。
    -- ============================
    State
    {
        name = "turret_walk",
        tags = { "busy", "noattack", "playing" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.components.combat:CancelAttack()
            inst.components.health:SetInvincible(true)

            local house = inst:FindTurretHouse()
            inst._turret_house = house

            if house == nil or not house:IsValid() then
                -- 岛上没有小屋：原地进入炮塔状态兜底
                inst:EnterHouse()
                inst.sg:GoToState("turret_active")
                return
            end

            local hx, _, hz = house.Transform:GetWorldPosition()
            local x, _, z = inst.Transform:GetWorldPosition()
            local walk_range = house_turret_tuning.WALK_RANGE * house_turret_tuning.WALK_RANGE

            if (hx - x) * (hx - x) + (hz - z) * (hz - z) > walk_range then
                -- 太远：直接传送到小屋门口
                local pt = inst:GetTurretDoorPoint(house)
                inst.Physics:SetCollides(false)
                inst.Physics:Teleport(pt.x, 0, pt.z)
                inst.Physics:SetCollides(true)
                inst.sg:GoToState("turret_enter")
                return
            end

            -- 较近：原版行走动画走向小屋，到达检测由模块的周期任务完成
            inst:ForceFacePoint(hx, 0, hz)
            inst.AnimState:PlayAnimation("walk_loop", true)
            inst:StartTurretApproach(house)
            inst.sg:SetTimeout(house_turret_tuning.WALK_TIMEOUT)
        end,

        ontimeout = function(inst)
            inst:EnterHouse()
            inst.sg:GoToState("turret_active")
        end,

        onexit = function(inst)
            inst:StopTurretApproach()
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
        end,
    },

    -- ============================
    -- 进屋动画：原版寄居蟹 gohome
    -- give 动画 + 定格第 5 帧，然后隐藏 Boss 进入炮塔状态。
    -- ============================
    State
    {
        name = "turret_enter",
        tags = { "busy", "noattack", "playing" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.components.combat:CancelAttack()
            inst.components.health:SetInvincible(true)

            local house = inst._turret_house
            if house ~= nil and house:IsValid() then
                local hx, _, hz = house.Transform:GetWorldPosition()
                inst:ForceFacePoint(hx, 0, hz)
            end

            -- 记录门口位置，出屋时回到这里
            inst._turret_door = inst:GetPosition()

            -- 原版寄居蟹 gohome：give 动画 + 定格第 5 帧
            inst.AnimState:PlayAnimation("give")
            inst.AnimState:SetFrame(5)

            inst.sg.statemem.enter_task = inst:DoTaskInTime(0.5, function()
                inst:EnterHouse()
                if inst.sg ~= nil then
                    inst.sg:GoToState("turret_active")
                end
            end)
            inst.sg:SetTimeout(1)
        end,

        ontimeout = function(inst)
            inst:EnterHouse()
            inst.sg:GoToState("turret_active")
        end,

        onexit = function(inst)
            if inst.sg.statemem.enter_task ~= nil then
                inst.sg.statemem.enter_task:Cancel()
                inst.sg.statemem.enter_task = nil
            end
        end,
    },

    -- ============================
    -- 炮塔阶段：Boss 隐藏在小屋中，小屋向玩家倾泻激光与导弹
    -- ============================
    State
    {
        name = "turret_active",
        tags = { "busy", "noattack", "playing" },

        onenter = function(inst)
            inst.components.locomotor:StopMoving()
            inst.Physics:Stop()
            inst.sg:SetTimeout(house_turret_tuning.DURATION)
        end,

        ontimeout = function(inst)
            inst:ExitHouse()
            inst.sg:GoToState("idle")
        end,

        onexit = function(inst)
            if not inst._surrendering and not inst._encounter_resolved then
                inst.components.health:SetInvincible(false)
            end
        end,
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
