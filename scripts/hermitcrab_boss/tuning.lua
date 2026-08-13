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

        ISLAND_RADIUS = 35,
        PLAYER_SCAN_PERIOD = 1,

        LASER_DAMAGE = 55,
        LASER_INTERVAL_MIN = 6,
        LASER_INTERVAL_MAX = 8,
        LASER_MIN_RADIUS = 5,
        LASER_MAX_RADIUS = 31,
        LASER_POINTS = 18,
        LASER_BEAM_COUNT = 3,
        LASER_POINT_INTERVAL = 2 * FRAMES,
        LASER_HIT_SCALE = 1.35,

        MISSILE_INTERVAL_MIN = 8,
        MISSILE_INTERVAL_MAX = 11,
        MISSILE_MAX_COUNT = 4,
        MISSILE_SHOW_DELAY = FRAMES,
    },
}
