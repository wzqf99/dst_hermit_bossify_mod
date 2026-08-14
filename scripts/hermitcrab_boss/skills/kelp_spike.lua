-- ============================================================================
-- 海带骨刺通用模块：hermitcrab_kelp_spike（竖立海带）的生成与参数注入。
-- 50% 的两个海带技能（kelp_snare 骨刺牢笼 / kelp_spiral 螺旋骨刺）共用，
-- 避免两处重复维护 SpawnSpikeAt；共享参数集中在 tuning.KELP_SPIKE。
-- ============================================================================

local tuning = require("hermitcrab_boss/tuning").KELP_SPIKE

local KelpSpike =
{
    PREFABS =
    {
        "hermitcrab_kelp_spike",
    },
}

-- 在指定点生成一根海带骨刺。
-- 参数：variation 外观变体（nil 时随机 1~7）；duration 存在时间；delay 冒出延迟。
function KelpSpike.SpawnSpikeAt(inst, x, z, variation, duration, delay)
    local spike = SpawnPrefab("hermitcrab_kelp_spike")
    if spike == nil then
        return nil
    end

    spike.Transform:SetPosition(x, 0, z)
    spike:SetAttacker(inst)

    -- 传入接触伤害参数（由 Boss 造成）。
    spike.contact_damage = tuning.SPIKE_DAMAGE
    spike.contact_radius = tuning.SPIKE_CONTACT_RADIUS
    spike.contact_cooldown = tuning.SPIKE_CONTACT_COOLDOWN
    -- 冒出动画速度倍率。
    spike.grow_speed = tuning.GROW_SPEED
    -- 冒出动画定格进度（长到该比例就冻结）。
    spike.grow_freeze_progress = tuning.GROW_FREEZE_PROGRESS

    local v = variation or math.random(7)
    if spike.RestartSpike ~= nil then
        spike:RestartSpike(delay or 0, duration or tuning.SPIKE_DURATION, v)
    end

    return spike
end

return KelpSpike
