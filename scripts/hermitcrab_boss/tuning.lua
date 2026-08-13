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

    FINAL_PHASE =
    {
        PHASE_HEALTH = 0.3,

        -- 房屋沿用 Boss 剩余生命，避免阶段切换时凭空恢复生命。
        HOUSE_MIN_HEALTH = 100,

        -- 房子头顶血条（原版 healthbar 组件）的显示参数
        HOUSE_HEALTHBAR_HEIGHT = 5,
        HOUSE_HEALTHBAR_WIDTH = 100,

        -- 蟹骑士：最终阶段在房子附近召唤一只
        HOUSE_KNIGHT_SPAWN_RADIUS = 4,
        HOUSE_KNIGHT_SPAWN_JITTER = 2,

        ISLAND_RADIUS = 35,
        PLAYER_SCAN_PERIOD = 1,

        -- 房屋近战反击/命中伤害（原激光伤害，保留给房屋 combat 使用）
        HOUSE_COMBAT_DAMAGE = 55,

        BOTTLE_DAMAGE = 55,
        BOTTLE_INTERVAL_MIN = 4,
        BOTTLE_INTERVAL_MAX = 6,
        BOTTLE_MAX_COUNT = 4,
        BOTTLE_THROW_STAGGER = 0.45,
        BOTTLE_SPEED = 12,
        BOTTLE_LAUNCH_HEIGHT = 2.5,
        BOTTLE_AIM_JITTER = 0.8,
        BOTTLE_DAMAGE_RADIUS = 2.5,

        MISSILE_INTERVAL_MIN = 8,
        MISSILE_INTERVAL_MAX = 11,
        MISSILE_MAX_COUNT = 4,
        MISSILE_SHOW_DELAY = FRAMES,
    },
}
