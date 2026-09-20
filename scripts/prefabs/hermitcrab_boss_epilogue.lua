-- ============================================================================
-- 胜利过场用的帝王蟹纯视觉实体。
--
-- 设计取舍：不复用原版 crabking prefab。原版帝王蟹自带 combat、血量、
-- 宝石插槽、冰场、生成器和掉落逻辑，直接拿来做过场会变成一个真正的 Boss
-- 实体（能被打、能反击、会掉东西）。这里只借用它的模型与动画资源，
-- 做成一个纯装饰实体（FX / DECOR / NOCLICK）。
--
-- 动画由 SGhermitcrab_boss_epilogue 驱动，原因见该文件顶部注释。
-- 台词复用寄居蟹隐士那套"头顶气泡"机制（talker + npc_talker），
-- 与 hermitcrab_boss/boss_talk.lua 完全一致的做法。
-- ============================================================================

local tuning = require("hermitcrab_boss/tuning").VICTORY_EPILOGUE

local assets =
{
    Asset("ANIM", "anim/crab_king_basic.zip"),
    Asset("ANIM", "anim/crab_king_actions.zip"),
    Asset("ANIM", "anim/crab_king_build.zip"),
    Asset("ANIM", "anim/crab_king_hole_build.zip"),
    Asset("SOUND", "sound/sfx.fsb"),
}

-- 台词表名（定义在 modmain.lua 的 STRINGS 中，客户端同样可解析）。
local TALK_STRING_TABLE = "CRABKING_EPILOGUE_TALK"

-- 说话音效：与隐士 boss 共用一个音效包，避免额外声明资源。
local TALK_SOUND = "hookline_2/creatures/boss/crabking/vocal"

local function CancelTask(inst, field)
    if inst[field] ~= nil then
        inst[field]:Cancel()
        inst[field] = nil
    end
end

-- ---------------------------------------------------------------------------
-- 说话：与 hermitcrab_boss/boss_talk.lua 的 SayThresholdLine 同构。
-- npc_talker:Chatter(表名, 索引) 里索引是数值下标，配合数组形式的台词表使用。
-- ---------------------------------------------------------------------------
local function SayLine(inst, index)
    if inst.components.npc_talker == nil
        or STRINGS[TALK_STRING_TABLE] == nil
        or STRINGS[TALK_STRING_TABLE][index] == nil then
        return
    end

    inst.components.npc_talker:Chatter(
        TALK_STRING_TABLE,
        index,
        CHATPRIORITIES.HIGH,
        true
    )
    inst.components.npc_talker:DoNextLine()
end

-- ---------------------------------------------------------------------------
-- 全部结束：通知逻辑层，并销毁自己。
-- 用 _epilogue_finished / _epilogue_cancelled 双标志保证回调只走一次。
-- ---------------------------------------------------------------------------
local function Finish(inst)
    if inst._epilogue_finished or inst._epilogue_cancelled then
        return
    end

    inst._epilogue_finished = true
    CancelTask(inst, "_line_task")
    CancelTask(inst, "_anim_timeout")

    if inst.components.npc_talker ~= nil then
        inst.components.npc_talker:ResetQueue()
    end
    if inst.components.talker ~= nil then
        inst.components.talker:ShutUp()
    end

    local finished = inst._finishedfn
    inst._finishedfn = nil
    if finished ~= nil then
        finished()
    end

    if inst:IsValid() then
        inst:Remove()
    end
end

-- ---------------------------------------------------------------------------
-- 开始下沉（台词说完后调用）
-- ---------------------------------------------------------------------------
local function StartDisappear(inst)
    if not inst:IsValid()
        or inst._epilogue_finished
        or inst._epilogue_cancelled
        or inst._phase == "disappear" then
        return
    end

    CancelTask(inst, "_line_task")
    CancelTask(inst, "_anim_timeout")
    inst._phase = "disappear"

    if inst.components.npc_talker ~= nil then
        inst.components.npc_talker:ResetQueue()
    end
    if inst.components.talker ~= nil then
        inst.components.talker:ShutUp()
    end

    -- 交给状态机播放，动画才会复制到客户端。
    if inst.sg ~= nil then
        inst.sg:GoToState("disappear")
    end

    -- 兜底：万一 animover 没触发，也能收尾，不会卡住整个结算流程。
    inst._anim_timeout = inst:DoTaskInTime(
        tuning.DISAPPEAR_FALLBACK,
        Finish
    )
end

-- ---------------------------------------------------------------------------
-- 逐句说台词；说完最后一句后进入下沉。
-- ---------------------------------------------------------------------------
local function SayNextLine(inst)
    if not inst:IsValid()
        or inst._epilogue_finished
        or inst._epilogue_cancelled
        or inst._phase ~= "dialogue" then
        return
    end

    local index = inst._line_index or 1
    if index > (tuning.LINE_COUNT or 3) then
        inst._line_task = inst:DoTaskInTime(
            tuning.POST_TALK_DELAY,
            StartDisappear
        )
        return
    end

    SayLine(inst, index)
    inst._line_index = index + 1
    inst._line_task = inst:DoTaskInTime(
        tuning.LINE_INTERVAL,
        SayNextLine
    )
end

-- ---------------------------------------------------------------------------
-- 出水动画播完 → 开始说台词。
-- 出水动画本身由状态机播；这里只负责逻辑层的启动，
-- 也因此重复调用（animover + 兜底超时）必须幂等。
-- ---------------------------------------------------------------------------
local function StartDialogue(inst)
    if not inst:IsValid()
        or inst._epilogue_finished
        or inst._epilogue_cancelled
        or inst._phase ~= "reappear" then
        return
    end

    CancelTask(inst, "_anim_timeout")
    inst._phase = "dialogue"
    inst._line_index = 1

    inst._line_task = inst:DoTaskInTime(
        tuning.DIALOGUE_DELAY,
        SayNextLine
    )
end

-- ---------------------------------------------------------------------------
-- 取消演出（战斗中断等），直接销毁，不回调 finished。
-- ---------------------------------------------------------------------------
local function Cancel(inst)
    if inst._epilogue_finished or inst._epilogue_cancelled then
        return
    end

    inst._epilogue_cancelled = true
    CancelTask(inst, "_line_task")
    CancelTask(inst, "_anim_timeout")
    inst._finishedfn = nil

    if inst.components.npc_talker ~= nil then
        inst.components.npc_talker:ResetQueue()
    end
    if inst.components.talker ~= nil then
        inst.components.talker:ShutUp()
    end

    if inst:IsValid() then
        inst:Remove()
    end
end

-- ---------------------------------------------------------------------------
-- 启动演出（由 victory_epilogue 模块在结算时调用）。
-- @param finishedfn 演出结束（已沉入海底并销毁前）的回调
-- @return boolean 是否成功启动
-- ---------------------------------------------------------------------------
local function Start(inst, finishedfn)
    if inst._epilogue_started then
        return false
    end

    inst._epilogue_started = true
    inst._finishedfn = finishedfn
    inst._phase = "reappear"

    if inst.sg ~= nil then
        inst.sg:GoToState("reappear")
    end

    inst._anim_timeout = inst:DoTaskInTime(
        tuning.REAPPEAR_FALLBACK,
        StartDialogue
    )
    return true
end

-- ---------------------------------------------------------------------------
-- 气泡说话配置（pristine 阶段，客户端也要执行）。
-- 参数与 hermitcrab_boss/boss_talk.lua 一致，保证观感统一。
-- ---------------------------------------------------------------------------
local function ConfigureTalker(inst)
    inst:AddComponent("talker")
    inst.components.talker.colour = Vector3(1, 0.45, 0.45)
    inst.components.talker.offset = Vector3(0, -400, 0)
    inst.components.talker.name_colour = Vector3(118 / 256, 89 / 256, 141 / 256)
    inst.components.talker.chaticon = "npcchatflair_hermitcrab"
    inst.components.talker:MakeChatter()
    inst.components.talker.lineduration = 3
    inst.components.talker.fontsize = 40
    inst.components.talker.font = TALKINGFONT_HERMIT or TALKINGFONT
    inst.components.talker.ontalk = function(entity)
        entity.SoundEmitter:PlaySound(TALK_SOUND)
    end

    inst:AddComponent("npc_talker")
    inst.components.npc_talker.default_chatpriority = CHATPRIORITIES.HIGH
end

local function OnReappearDone(inst)
    StartDialogue(inst)
end

local function OnDisappearDone(inst)
    Finish(inst)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.Transform:SetScale(tuning.SCALE, tuning.SCALE, tuning.SCALE)

    inst.AnimState:SetBank("king_crab")
    inst.AnimState:SetBuild("crab_king_build")
    inst.AnimState:AddOverrideBuild("crab_king_hole_build")
    -- 与 prefabs/crabking.lua 第 1598 行完全一致：不带循环参数，
    -- 循环与否交给状态机的 inert 状态决定，避免两处重复指定产生歧义。
    inst.AnimState:PlayAnimation("inert")
    -- 原版帝王蟹在水面时把水面遮罩藏起来，这里保持一致。
    inst.AnimState:Hide("water")

    -- 纯装饰：不可点击、不阻挡、不打乱寻路。
    inst:AddTag("FX")
    inst:AddTag("DECOR")
    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")
    inst:AddTag("ignorewalkableplatforms")

    -- 气泡说话组件在 pristine 阶段配置，客户端同样需要（与 boss_talk 一致）。
    ConfigureTalker(inst)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst:SetStateGraph("SGhermitcrab_boss_epilogue")

    inst.StartVictoryEpilogue = Start
    inst.CancelVictoryEpilogue = Cancel

    inst:ListenForEvent("epilogue_reappear_done", OnReappearDone)
    inst:ListenForEvent("epilogue_disappear_done", OnDisappearDone)

    -- 被外力销毁（战斗中断等）时，清理任务并补一次回调，
    -- 否则结算流程会永远等不到 finished 而卡住。
    inst:ListenForEvent("onremove", function(entity)
        CancelTask(entity, "_line_task")
        CancelTask(entity, "_anim_timeout")
        if entity._epilogue_started
            and not entity._epilogue_finished
            and not entity._epilogue_cancelled then
            entity._epilogue_finished = true
            local finished = entity._finishedfn
            entity._finishedfn = nil
            if finished ~= nil then
                finished()
            end
        end
    end)

    return inst
end

return Prefab("hermitcrab_boss_epilogue", fn, assets)
