-- ============================================================================
-- 奶奶身体周围的月亮氛围：发光（蓝白冷光）+ 掉理智光环，随战斗阶段增强，
-- 与裂隙月相等级（fissure.lua）严格同步。
--
--   - 90% 弦月：微光 + 微弱掉理智
--   - 75% 半月：渐亮
--   - 50% 月盈月亏：明显
--   - 30% 满月：全亮 + 最强掉理智
--
-- Light 组件在 prefab 的 pristine 阶段通过 entity:AddLight() 添加。
-- 关键：Light 的显示在客户端，因此渐变任务必须在 pristine 阶段注册
-- （Configure），让客户端和服务器都跑；等级用 net 变量同步。
-- ============================================================================

local events = require("hermitcrab_boss/events")
local fissure_tuning = require("hermitcrab_boss/tuning").FISSURES
local aura_tuning = require("hermitcrab_boss/tuning").MOON_AURA

local MoonAura =
{
    PREFABS =
    {
        "moon_altar_link_fx",
    },
}

-- Light 逐帧渐变速率（同原版 moon_fissure）。
local LIGHT_RADIUS_RATE = 1 / (12 * FRAMES)

-- 粒子生成任务间隔（秒）。
local PARTICLE_TICK = 0.25

-- 逐帧把 Light 参数平滑过渡到当前等级的目标值（客户端 + 服务器都跑）。
local function OnUpdateAuraLight(inst)
    local level = inst._moon_aura_level ~= nil and inst._moon_aura_level:value() or 1
    local data = aura_tuning.LEVELS[level] or aura_tuning.LEVELS[1]

    local world_brightness = TheWorld.components.ambientlighting:GetVisualAmbientValue()
    local dt = FRAMES

    local cur_radius = inst.Light:GetRadius()
    inst.Light:SetRadius(cur_radius + (data.radius - cur_radius) * dt * LIGHT_RADIUS_RATE)

    local cur_intensity = inst.Light:GetIntensity()
    inst.Light:SetIntensity(cur_intensity + (data.intensity - cur_intensity) * dt * LIGHT_RADIUS_RATE)

    local cur_falloff = inst.Light:GetFalloff()
    inst.Light:SetFalloff(cur_falloff + (data.falloff - cur_falloff) * dt * LIGHT_RADIUS_RATE)

    inst.Light:Enable(data.enabled)

    local cs = (1 - world_brightness * 0.25)
    local r, g, b = aura_tuning.COLOUR[1], aura_tuning.COLOUR[2], aura_tuning.COLOUR[3]
    inst.Light:SetColour(r * cs, g * cs, b * cs)
end

-- sanityaura 动态值：按当前等级返回掉理智强度（仅服务器）。
local function aurafn(inst, observer)
    local level = inst._moon_aura_level ~= nil and inst._moon_aura_level:value() or 1
    local data = aura_tuning.LEVELS[level] or aura_tuning.LEVELS[1]
    return data.sanity
end

-- 设置月相等级（服务器）：同步 net 变量 + 更新理智光环范围。
local function SetAuraLevel(inst, level)
    if inst._moon_aura_level ~= nil and inst._moon_aura_level:value() == level then
        return
    end

    if inst._moon_aura_level ~= nil then
        inst._moon_aura_level:set(level)
    else
        inst._moon_aura_level = level
    end

    local data = aura_tuning.LEVELS[level] or aura_tuning.LEVELS[1]
    if inst.components.sanityaura ~= nil then
        inst.components.sanityaura.max_distsq = data.radius * data.radius * 1.25 * 1.25
    end
end

-- 在 Boss 周围随机位置生成一个飘浮天体光点（一次性动画，自动消失）。
local function SpawnMoonParticle(inst)
    local angle = math.random() * TWOPI
    local x, y, z = inst.Transform:GetWorldPosition()

    local px = x + math.cos(angle) * aura_tuning.PARTICLE_RADIUS
    local pz = z - math.sin(angle) * aura_tuning.PARTICLE_RADIUS
    local py = y + aura_tuning.PARTICLE_HEIGHT_MIN
        + math.random() * (aura_tuning.PARTICLE_HEIGHT_MAX - aura_tuning.PARTICLE_HEIGHT_MIN)

    local fx = SpawnPrefab(aura_tuning.PARTICLE_PREFAB)
    if fx ~= nil then
        fx.Transform:SetPosition(px, py, pz)
    end
end

-- 粒子生成任务：按当前等级的生成率在 Boss 周围撒光点（服务器）。
local function OnParticleTick(inst)
    local level = inst._moon_aura_level ~= nil and inst._moon_aura_level:value() or 1
    local rate = aura_tuning.PARTICLE_RATE[level] or 0
    if rate <= 0 then
        return
    end

    local expected = rate * PARTICLE_TICK
    local whole = math.floor(expected)
    for _ = 1, whole do
        SpawnMoonParticle(inst)
    end
    if math.random() < (expected - whole) then
        SpawnMoonParticle(inst)
    end
end

-- ---------------------------------------------------------------------------
-- pristine 阶段调用：注册 net 变量 + Light 渐变任务（客户端/服务器都跑）。
-- ---------------------------------------------------------------------------
function MoonAura.Configure(inst)
    inst._moon_aura_level = net_tinybyte(inst.GUID, "moonaura.level", "moonauradirty")
    inst._moon_aura_level:set(1)

    inst._moon_aura_lighttask = inst:DoPeriodicTask(0, OnUpdateAuraLight)
    OnUpdateAuraLight(inst)
end

-- ---------------------------------------------------------------------------
-- master sim 调用：加 sanityaura + 监听阶段事件。
-- ---------------------------------------------------------------------------
function MoonAura.Attach(inst)
    inst:AddComponent("sanityaura")
    inst.components.sanityaura.aurafn = aurafn
    inst.components.sanityaura.max_distsq = 0

    -- 与裂隙月相等级同步：复用 fissure 的同一套阶段事件与等级常量。
    inst:ListenForEvent(events.GUARD_SUMMON, function()
        SetAuraLevel(inst, fissure_tuning.OPEN_LEVEL)
    end)
    inst:ListenForEvent(events.SHELL_PHASE, function()
        SetAuraLevel(inst, fissure_tuning.SHELL_LEVEL)
    end)
    inst:ListenForEvent(events.KELP_SNARE, function()
        SetAuraLevel(inst, fissure_tuning.SNARE_LEVEL)
    end)
    inst:ListenForEvent(events.FINAL_PHASE_STARTED, function()
        SetAuraLevel(inst, fissure_tuning.FINAL_LEVEL)
    end)
    -- 战斗结束：熄灭月光、清空理智光环。
    inst:ListenForEvent(events.ENCOUNTER_FINISHED, function()
        SetAuraLevel(inst, 1)
    end)

    -- 环绕天体粒子生成任务（服务器，光点一次性动画自动消失）。
    inst._moon_aura_particletask = inst:DoPeriodicTask(PARTICLE_TICK, OnParticleTick)

    -- 实体移除时清理任务。
    inst:ListenForEvent("onremove", function()
        if inst._moon_aura_lighttask ~= nil then
            inst._moon_aura_lighttask:Cancel()
            inst._moon_aura_lighttask = nil
        end
        if inst._moon_aura_particletask ~= nil then
            inst._moon_aura_particletask:Cancel()
            inst._moon_aura_particletask = nil
        end
    end)
end

return MoonAura
