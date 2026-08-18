local events = require("hermitcrab_boss/events")
local tuning = require("hermitcrab_boss/tuning").ENCOUNTER

local Encounter =
{
    FINISHING_EVENT = events.ENCOUNTER_FINISHING,
    FINISHED_EVENT = events.ENCOUNTER_FINISHED,
    PREFABS =
    {
        "hermit_pearl",
    },
}

local function HasNearbyLivingPlayer(inst)
    for _, player in ipairs(AllPlayers) do
        if player:IsValid()
            and not player:HasTag("playerghost")
            and not player:IsInLimbo()
            and inst:IsNear(player, tuning.PLAYER_DISTANCE) then
            return true
        end
    end

    return false
end

local function Watch(inst)
    if inst._encounter_resolved or inst._surrendering then
        return
    end

    if HasNearbyLivingPlayer(inst) then
        inst._empty_encounter_time = 0
    else
        inst._empty_encounter_time = inst._empty_encounter_time + tuning.WATCH_PERIOD
        if inst._empty_encounter_time >= tuning.EMPTY_TIMEOUT then
            inst:FinishEncounter(false)
        end
    end
end

local function BeginSurrender(inst)
    if inst._surrendering or inst._encounter_resolved then
        return
    end

    inst._surrendering = true
    -- 本体血量归零时，投降状态就是胜利动画本身；结算必须等状态结束。
    inst._victory_animation_started = true
    inst._victory_animation_finished = nil
    inst.components.health:SetInvincible(true)
    inst.components.combat:SetTarget(nil)
    inst.components.combat:CancelAttack()
    inst:PushEvent(events.SURRENDER)
end

local function OnHealthDelta(inst)
    if not inst._final_phase_triggered
        and inst.components.health.currenthealth <= inst.components.health.minhealth then
        BeginSurrender(inst)
    end
end

local function LearnPearlReward(hermit)
    if hermit.components.craftingstation ~= nil
        and not hermit.components.craftingstation:KnowsItem("winter_ornament_boss_pearl") then
        hermit.components.craftingstation:LearnItem(
            "winter_ornament_boss_pearl",
            "hermitshop_winter_ornament_boss_pearl"
        )
    end
end

-- 最终阶段的胜利由房屋 minhealth 事件触发，不会经过本体的 healthdelta。
-- 先拆掉房屋防御并让隐藏的 Boss 重新出现，再由 surrender 状态完成结算。
local function StartVictoryAnimation(inst)
    if inst._victory_animation_started
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    inst._victory_animation_started = true
    inst._victory_animation_finished = nil
    inst._surrendering = true
    inst.components.health:SetInvincible(true)
    inst.components.combat:SetTarget(nil)
    inst.components.combat:CancelAttack()

    if inst._watch_task ~= nil then
        inst._watch_task:Cancel()
        inst._watch_task = nil
    end

    -- ENCOUNTER_FINISHING 会清理房屋、飞弹、瓶子和最终阶段小怪。
    inst:PushEvent(Encounter.FINISHING_EVENT, { victory = true, animation = true })

    -- 最终阶段时 Boss 被 Hide() 并关闭了阴影；投降动画需要重新展示本体。
    inst:Show()
    if inst.DynamicShadow ~= nil then
        inst.DynamicShadow:Enable(true)
    end
    inst:RemoveTag("invisible")
    inst:RemoveTag("NOCLICK")

    inst:PushEvent(events.SURRENDER)
end

local function Finish(inst, victory, already_removing)
    if inst._encounter_resolved then
        return
    end

    -- 房屋被击破时第一次调用只负责启动动画；动画期间的重复结算事件应忽略。
    if victory and not inst._victory_animation_started then
        StartVictoryAnimation(inst)
        return
    elseif victory
        and not inst._victory_animation_finished then
        return
    end

    inst._encounter_resolved = true

    if inst._watch_task ~= nil then
        inst._watch_task:Cancel()
        inst._watch_task = nil
    end

    -- 最终阶段需要先恢复房屋并释放真实寄居蟹，后续奖励和归还逻辑才能沿用。
    inst:PushEvent(Encounter.FINISHING_EVENT, { victory = victory })

    local hermit = inst._encounter_hermit
    if hermit ~= nil then
        if inst._on_hermit_removed ~= nil then
            inst:RemoveEventCallback("onremove", inst._on_hermit_removed, hermit)
            inst._on_hermit_removed = nil
        end

        if hermit:IsValid() then
            if victory and not hermit.pearlgiven then
                hermit.pearlgiven = true
                local pearl = SpawnPrefab("hermit_pearl")
                if pearl ~= nil then
                    pearl.Transform:SetPosition(inst.Transform:GetWorldPosition())
                    LearnPearlReward(hermit)
                else
                    hermit.pearlgiven = nil
                end
            end

            if hermit._hermitcrab_boss == inst then
                hermit._hermitcrab_boss = nil
            end

            if hermit:IsInLimbo() then
                hermit:ReturnToScene()
            end
        end
    end

    -- 技能模块在这里清理场上实体，并在奶奶回到场景后结算关联状态。1
    inst:PushEvent(Encounter.FINISHED_EVENT, {
        hermit = hermit ~= nil and hermit:IsValid() and hermit or nil,
        victory = victory,
    })

    if inst._on_hermit_relocated ~= nil then
        inst:RemoveEventCallback("ms_hermitcrab_relocated", inst._on_hermit_relocated, TheWorld)
        inst._on_hermit_relocated = nil
    end

    if TheWorld._hermitcrab_boss == inst then
        TheWorld._hermitcrab_boss = nil
    end

    inst._encounter_hermit = nil

    if not already_removing and inst:IsValid() then
        inst:Remove()
    end
end

local function SetHermit(inst, hermit, challenger)
    inst._encounter_hermit = hermit
    inst._empty_encounter_time = 0

    local island_marker = hermit.CHEVO_marker
    if island_marker == nil or not island_marker:IsValid() then
        island_marker = FindEntity(hermit, 35, nil, { "hermitcrab_marker" })
    end
    inst._island_center = island_marker ~= nil
        and island_marker:GetPosition()
        or inst:GetPosition()

    inst.components.knownlocations:RememberLocation("home", inst:GetPosition())

    inst._on_hermit_removed = function()
        inst._encounter_hermit = nil
        inst._on_hermit_removed = nil
        if inst:IsValid() then
            inst:FinishEncounter(false)
        end
    end
    inst:ListenForEvent("onremove", inst._on_hermit_removed, hermit)

    inst._on_hermit_relocated = function()
        if inst:IsValid() then
            inst:FinishEncounter(false)
        end
    end
    inst:ListenForEvent("ms_hermitcrab_relocated", inst._on_hermit_relocated, TheWorld)

    if challenger ~= nil and challenger:IsValid() then
        inst.components.combat:SetTarget(challenger)
    end

    inst._watch_task = inst:DoPeriodicTask(
        tuning.WATCH_PERIOD,
        Watch,
        tuning.WATCH_PERIOD
    )
end

local function OnRemoveEntity(inst)
    inst:FinishEncounter(false, true)
end

function Encounter.Attach(inst)
    inst.SetEncounterHermit = SetHermit
    inst.FinishEncounter = Finish
    inst.OnRemoveEntity = OnRemoveEntity

    inst:ListenForEvent("healthdelta", OnHealthDelta)
end

return Encounter
