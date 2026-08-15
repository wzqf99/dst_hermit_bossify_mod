-- ============================================================================
-- Boss 血线台词模块
-- 复刻原版寄居蟹隐士的"头顶冒字"机制（talker + npc_talker 组件）：
--   - talker 在 pristine 阶段配置（客户端也执行），负责气泡渲染与网络同步；
--   - 服务器端监听 healthdelta，在 Boss 血量跨过 90% / 70% / 50% / 30% 时
--     通过 npc_talker:Chatter 说一句符合当前战况的台词。
-- 台词文本定义在 modmain.lua 的 STRINGS.HERMITCRAB_BOSS_TALK（客户端可解析）。
-- ============================================================================
-- 注意：本模块由 prefab 文件 require，加载环境与原版 prefab 一致。
-- 在此环境中可直接使用 TALKINGFONT_HERMIT、CHATPRIORITIES、STRINGS 等全局
-- 变量（与原版 hermitcrab.lua 相同），切勿加 GLOBAL. 前缀，否则 strict 模式
-- 下会因 "variable 'GLOBAL' is not declared" 而崩溃。
local BossTalk = {}

-- 台词文本表名（STRINGS 里的顶层键）。
local STR_TBL = "HERMITCRAB_BOSS_TALK"

-- 血量台词阈值（从高到低），每档只触发一次。
BossTalk.TALK_THRESHOLDS =
{
    0.9,
    0.7,
    0.5,
    0.3,
}

-- 说话音效：复用原版寄居蟹说话音效（hookline_2 音效随 sfx.fsb 加载）。
local function ontalk(inst)
    inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/talk")
end

-- pristine 阶段配置（客户端与服务器都执行）：添加 talker / npc_talker。
function BossTalk.Configure(inst)
    inst:AddComponent("talker")
    inst.components.talker.colour = Vector3(1, 0.45, 0.45)
    inst.components.talker.offset = Vector3(0, -400, 0)
    inst.components.talker.name_colour = Vector3(118 / 256, 89 / 256, 141 / 256)
    inst.components.talker.chaticon = "npcchatflair_hermitcrab"
    inst.components.talker:MakeChatter()
    inst.components.talker.lineduration = 3
    inst.components.talker.fontsize = 40
    inst.components.talker.font = TALKINGFONT_HERMIT or TALKINGFONT

    inst:AddComponent("npc_talker")
    inst.components.npc_talker.default_chatpriority = CHATPRIORITIES.LOW
end

-- 服务器端：说某一档台词（从 STRINGS 随机选一句）。
local function SayThresholdLine(inst, threshold)
    -- STRINGS 与 chatter 解析均使用字符串 key（如 "90"），故转成字符串再查表。
    local key = tostring(math.floor(threshold * 100)) -- "90" / "70" / "50" / "30"
    local lines = STRINGS[STR_TBL] and STRINGS[STR_TBL][key]
    if lines == nil or #lines == 0 then
        return
    end

    inst.components.npc_talker:Chatter(STR_TBL .. "." .. key, math.random(#lines))
    inst.components.npc_talker:DoNextLine()
end

local function OnHealthDelta(inst, data)
    if inst._encounter_resolved or inst._surrendering then
        return
    end
    if data == nil
        or data.oldpercent == nil
        or data.newpercent == nil
        or data.newpercent >= data.oldpercent then
        return
    end

    -- 一次掉血跨过多个阈值时，只触发最深（阈值最低）的一档，
    -- 避免连说多句互相打断（talker:Say 会取消上一个任务）。
    local deepest = nil
    for _, threshold in ipairs(BossTalk.TALK_THRESHOLDS) do
        if not inst._talked_thresholds[threshold]
            and data.oldpercent > threshold
            and data.newpercent <= threshold then
            if deepest == nil or threshold < deepest then
                deepest = threshold
            end
        end
    end

    if deepest ~= nil then
        inst._talked_thresholds[deepest] = true
        SayThresholdLine(inst, deepest)
    end
end

function BossTalk.Attach(inst)
    inst._talked_thresholds = inst._talked_thresholds or {}

    if inst.components.talker ~= nil then
        inst.components.talker.ontalk = ontalk
    end

    inst:ListenForEvent("healthdelta", OnHealthDelta)
end

return BossTalk
