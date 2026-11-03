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
        -- 牢笼专用：出生即带障碍物理（挡角色），见 prefabs/hermitcrab_kelp_spike.lua。
        "hermitcrab_kelp_spike_wall",
    },
}

-- 在指定点生成一根海带骨刺。
-- 参数：variation 外观变体（nil 时随机 1~7）；duration 存在时间；delay 冒出延迟；
--       blocking 是否生成带碰撞体积的"牢笼刺"（螺旋 / 房屋不传）。
function KelpSpike.SpawnSpikeAt(inst, x, z, variation, duration, delay, blocking)
    local spike = SpawnPrefab(
        blocking and "hermitcrab_kelp_spike_wall" or "hermitcrab_kelp_spike"
    )
    -- 兜底：牢笼刺 prefab 未注册时退回纯视觉刺，至少保证技能有表现。
    if spike == nil and blocking then
        spike = SpawnPrefab("hermitcrab_kelp_spike")
    end
    if spike == nil then
        return nil
    end

    spike.Transform:SetPosition(x, 0, z)
    spike:SetAttacker(inst)

    -- 牢笼刺按调参设置碰撞半径（能否从缝隙挤出取决于它与圈半径的比例）。
    if blocking and spike.Physics ~= nil and tuning.SPIKE_COLLISION_RADIUS ~= nil then
        spike.Physics:SetCapsule(tuning.SPIKE_COLLISION_RADIUS, 2)
    end

    -- 传入伤害参数（一次性结算，由 Boss 造成）。
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
