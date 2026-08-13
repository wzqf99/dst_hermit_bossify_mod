local BASE_DAMAGE = 40

return
{
    MAX_HEALTH = 5200,
    DAMAGE = BASE_DAMAGE,
    ATTACK_PERIOD = 2,
    TARGET_DISTANCE = 20,
    KEEP_TARGET_DISTANCE = 30,

    ENCOUNTER =
    {
        PLAYER_DISTANCE = 35,
        EMPTY_TIMEOUT = 10,
        WATCH_PERIOD = 2,
    },

    SHELL_RING =
    {
        PHASE_HEALTH = 0.75,
        COUNT = 6,
        CONTACT_DAMAGE = BASE_DAMAGE,
        CONTACT_COOLDOWN = 1,
        WATER_MIN_RADIUS = 22,
        WATER_MAX_RADIUS = 40,
        WATER_FALLBACK_RADIUS = 55,
        SALVAGE_RADIUS = 45,
        WATER_POINT_MIN_SPACING = 5,
    },

    GUARD_SUMMON =
    {
        PHASE_HEALTH = 0.5,
        COUNT = 3,
        SPAWN_MIN_RADIUS = 2,
        SPAWN_MAX_RADIUS = 5,
        SPAWN_ATTEMPTS = 30,
    },

    HOUSE_TURRET =
    {
        PHASE_HEALTH = 0.3,          -- 30% 血量触发炮塔阶段
        DURATION = 15,               -- 屋内炮塔持续时间（秒）
        WALK_RANGE = 40,             -- 距小屋 ≤40 走路进屋，更远直接传送
        WALK_TIMEOUT = 8,            -- 走路兜底超时（秒）
        ATTACK_RANGE = 35,           -- 炮塔射程（以小屋为中心）
        LASER_INTERVAL = 2.5,        -- 每轮激光间隔（秒）
        LASER_COUNT = 2,             -- 每轮激光线条数（红蓝交替）
        LASER_DAMAGE = 60,           -- 每发激光伤害（混用巨鹿/天体英雄激光）
        LASER_STEPS = 8,             -- 每条激光线的分段数（点越密光线越连续）
        MISSILE_INTERVAL = 5,        -- 每轮导弹间隔（秒）
        MISSILE_COUNT = 3,           -- 每轮导弹数量
        MISSILE_DAMAGE = 40,         -- 每枚导弹伤害
        HEAT_SCAN_RANGE = 12,        -- 优先锁定热源（星星/暖石）的扫描半径
        HOUSE_SEARCH_RANGE = 80,     -- 找不到小屋时的兜底搜索半径
    },
}
