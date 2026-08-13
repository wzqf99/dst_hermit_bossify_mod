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
}
