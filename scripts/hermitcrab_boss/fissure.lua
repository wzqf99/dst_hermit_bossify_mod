-- 岛上的堵住裂缝 Boss 战强化：
-- 90% 血时将堵住裂缝替换为真正的天体裂缝（moon_fissure）并播打开动画，
-- 之后随战斗阶段推进逐级"变大"（月相等级 1~5：发光渐强、理智光环渐强）。
-- 只操作本 Boss 打开的那些裂隙，不影响地图上其他原版天体裂缝。
local events = require("hermitcrab_boss/events")

local Fissure = {}
local tuning = require("hermitcrab_boss/tuning").FISSURES

local MOON_STATES =
{
    new          = 1,
    quarter      = 2,
    half         = 3,
    threequarter = 4,
    full         = 5,
}

-- 只保留等级相关的视觉/光环数据（与原版 lightstate_data 对应）。
local LIGHTSTATE_DATA =
{
    {enabled = false, radius = 0.0,  layers = {low = false, med = false, high = false, full = false}},
    {enabled = true,  radius = 3.0,  layers = {low = true,  med = false, high = false, full = false}},
    {enabled = true,  radius = 6.0,  layers = {low = true,  med = true,  high = false, full = false}},
    {enabled = true,  radius = 11.0, layers = {low = true,  med = true,  high = true,  full = false}},
    {enabled = true,  radius = 11.0, layers = {low = true,  med = true,  high = true,  full = true }},
}

-- 去掉可交互组件：原版 moon_fissure 带 repairable/workable，
-- 玩家战斗中如果把月亮部件插进去会把裂缝替换成月亮祭坛（原版 on_piece_slotted），破坏机制。
local function StripInteractions(fissure)
    if fissure.components.repairable ~= nil then
        fissure:RemoveComponent("repairable")
    end
    if fissure.components.workable ~= nil then
        fissure:RemoveComponent("workable")
    end
end

-- 把裂隙强制设置到指定月相等级（只改状态，不走原版 transition 动画）。
-- 灯光会由 moon_fissure 自带的逐帧渐变任务自动过渡到新等级。
local function SetFissureLevel(fissure, level)
    if fissure == nil or not fissure:IsValid() then
        return
    end

    local lightstate = LIGHTSTATE_DATA[level] or LIGHTSTATE_DATA[1]
    for layer, enable in pairs(lightstate.layers) do
        fissure.AnimState:Hide(layer)
        fissure.fx.AnimState:Hide(layer)
        if enable then
            fissure.fx.AnimState:Show(layer)
        end
    end
    if lightstate.enabled then
        fissure.fx.AnimState:Show("backing")
        fissure.AnimState:Hide("backing")
    else
        fissure.fx.AnimState:Hide("backing")
        fissure.AnimState:Show("backing")
    end

    fissure.Light:Enable(lightstate.enabled)
    if fissure.components.sanityaura ~= nil then
        fissure.components.sanityaura.max_distsq =
            lightstate.radius * lightstate.radius * 1.25 * 1.25
    end
    fissure._level:set(level)
end

-- 90% 血：把岛上所有堵住裂缝替换成打开的天体裂缝并记录到 Boss。
local function OpenIslandFissures(inst)
    if inst._opened_fissures ~= nil then
        return
    end
    inst._opened_fissures = {}

    -- 先收集再处理，避免遍历时修改 Ents。
    local plugged = {}
    for _, v in pairs(Ents) do
        if v:IsValid() and v.prefab ~= nil and v.prefab == "moon_fissure_plugged" then
            table.insert(plugged, v)
        end
    end

    for _, v in ipairs(plugged) do
        local x, y, z = v.Transform:GetWorldPosition()
        v:Remove()

        local fissure = SpawnPrefab("moon_fissure")
        if fissure ~= nil then
            fissure.Transform:SetPosition(x, y, z)
            StripInteractions(fissure)
            -- 播一次"打开"过渡动画，再回到裂缝 idle 循环。
            fissure.AnimState:PlayAnimation("transition")
            fissure.AnimState:PushAnimation("crack_idle", true)
            fissure.fx.AnimState:PlayAnimation("transition")
            fissure.fx.AnimState:PushAnimation("crack_idle", true)
            fissure.SoundEmitter:PlaySound("turnoftides/common/together/moon_fissure/crack_open")
            table.insert(inst._opened_fissures, fissure)
        end
    end
end

local function SetOpenedFissuresLevel(inst, level)
    if inst._opened_fissures == nil then
        return
    end
    for _, fissure in ipairs(inst._opened_fissures) do
        SetFissureLevel(fissure, level)
    end
end

-- 战斗结束：让裂隙恢复跟随真实月相。
local function RestoreFissures(inst)
    if inst._opened_fissures == nil then
        return
    end
    local real_level = MOON_STATES[TheWorld.state.moonphase] or MOON_STATES.new
    for _, fissure in ipairs(inst._opened_fissures) do
        SetFissureLevel(fissure, real_level)
    end
end

-- 对外接口：返回已打开的裂隙坐标（含可通过性过滤），
-- 供最终阶段召唤蟹骑士/蟹卫使用。裂隙未打开时返回空表。
-- 返回坐标而非实体引用，避免调用方与内部实现（_opened_fissures）耦合。
function Fissure.GetOpenedFissurePoints(inst)
    local points = {}
    if inst._opened_fissures == nil then
        return points
    end
    for _, fissure in ipairs(inst._opened_fissures) do
        if fissure ~= nil and fissure:IsValid() then
            local x, _, z = fissure.Transform:GetWorldPosition()
            if TheWorld.Map:IsPassableAtPoint(x, 0, z) then
                table.insert(points, Vector3(x, 0, z))
            end
        end
    end
    return points
end

function Fissure.Attach(inst)
    inst.OpenIslandFissures = OpenIslandFissures
    inst.GetOpenedFissurePoints = Fissure.GetOpenedFissurePoints

    -- 90% 蟹卫召唤：打开裂隙并进入弦月。
    inst:ListenForEvent(events.GUARD_SUMMON, function()
        OpenIslandFissures(inst)
        SetOpenedFissuresLevel(inst, tuning.OPEN_LEVEL)
    end)
    -- 75% 贝壳环：半月。
    inst:ListenForEvent(events.SHELL_PHASE, function()
        SetOpenedFissuresLevel(inst, tuning.SHELL_LEVEL)
    end)
    -- 50% 海带骨刺：月盈月亏。
    inst:ListenForEvent(events.KELP_SNARE, function()
        SetOpenedFissuresLevel(inst, tuning.SNARE_LEVEL)
    end)
    -- 30% 最终阶段：满月（全亮、理智光环最高）。
    -- 兜底：若跳级伤害直接进入最终阶段（裂隙可能还没打开），这里先打开再升满月。
    inst:ListenForEvent(events.FINAL_PHASE_STARTED, function()
        OpenIslandFissures(inst)
        SetOpenedFissuresLevel(inst, tuning.FINAL_LEVEL)
    end)
    -- 战斗结束：恢复真实月相。
    inst:ListenForEvent(events.ENCOUNTER_FINISHED, function()
        RestoreFissures(inst)
    end)
end

return Fissure
