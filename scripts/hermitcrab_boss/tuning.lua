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

    -- 海带骨刺共享参数：50% 的两个海带技能（牢笼 / 螺旋）共用。
    KELP_SPIKE =
    {
        -- 海带刺持续时间（秒）
        SPIKE_DURATION = 6,

        -- 海带冒出（grow）动画播放速度倍率：<1 减慢，1 = 原速。
        -- 0.8 = grow 完整约 1.25 秒，长到定格（0.4 进度）约 0.5 秒，让玩家尽早反应。
        GROW_SPEED = 0.8,

        -- grow 动画定格进度（0~1）：海带长到该比例时就冻结定格，不再继续长满。
        -- 0.4 = 叶子长到四成。
        GROW_FREEZE_PROGRESS = 0.4,

        -- 海带刺接触伤害：海带竖立期间持续生效，由 Boss 造成（仇恨归属 Boss）。
        SPIKE_DAMAGE = BASE_DAMAGE,
        SPIKE_CONTACT_RADIUS = 1.6,
        SPIKE_CONTACT_COOLDOWN = 1,
    },

    -- 海带骨刺技能·牢笼：50% 血量触发（与蟹卫召唤对调后）。
    -- 围绕每个玩家生成一圈海带刺，形成牢笼。
    -- 首次释放后每 REPEAT_INTERVAL 秒循环施放一次，直到钻入屋子（30% 最终阶段）。
    KELP_SNARE =
    {
        PHASE_HEALTH = 0.5,

        SNARE_RANGE = 40,
        SNARE_MAX_RANGE = 45,

        -- 循环施放间隔（秒）：50% 首次释放后每 8 秒重放一次牢笼，
        -- 直到 Boss 钻入屋子（30% 最终阶段）或投降 / 战斗结束。
        REPEAT_INTERVAL = 8,
    },

    -- 海带骨刺技能·螺旋：50% 血量触发。
    -- 从 Boss 脚下以阿基米德螺旋扩散，逐个延迟冒出。
    KELP_SPIRAL =
    {
        PHASE_HEALTH = 0.5,

        -- 螺旋骨刺：从 Boss 脚下螺旋扩散
        -- 总覆盖半径 ≈ SPIRAL_START_RADIUS + SPIRAL_COUNT * SPIRAL_RADIUS_STEP ≈ 16.5
        SPIRAL_COUNT = 40,
        SPIRAL_SPACING = 0.6,
        SPIRAL_START_RADIUS = 0.5,
        SPIRAL_RADIUS_STEP = 0.4,
        SPIRAL_DELAY_PER_STEP = 0.03,

        -- 铺蛛网：螺旋骨刺释放前在 Boss 脚下铺一片蛛网减速玩家（不影响 Boss 自己）。
        WEB_RADIUS = 6,              -- 单片蛛网的减速半径（与原版 BOOK_WEB_GROUND_RADIUS 一致）
        WEB_SPEED_PENALTY = 0.3,     -- 减速后速度比例（越小越慢）
        WEB_DURATION = 10,           -- 蛛网持续时间（秒）
        WEB_VISUAL_SCALE = 1.25,     -- 蛛网视觉缩放（与原版 book_web_ground 一致）
    },

    SHELL_RING =
    {
        PHASE_HEALTH = 0.75,
        COUNT = 6,
        CONTACT_DAMAGE = BASE_DAMAGE,
        CONTACT_COOLDOWN = 1,
        -- 每枚贝壳累计碰撞多少次后破碎
        MAX_CONTACTS = 3,
        WATER_MIN_RADIUS = 22,
        WATER_MAX_RADIUS = 40,
        WATER_FALLBACK_RADIUS = 55,
        SALVAGE_RADIUS = 45,
        WATER_POINT_MIN_SPACING = 5,
    },

    GUARD_SUMMON =
    {
        PHASE_HEALTH = 0.9,
        COUNT = 3,
        SPAWN_MIN_RADIUS = 2,
        SPAWN_MAX_RADIUS = 5,
        SPAWN_ATTEMPTS = 30,
    },

    -- 堵住裂缝 Boss 战强化：随战斗阶段推进逐级"变大"（月相等级 1~5）。
    FISSURES =
    {
        OPEN_LEVEL  = 2, -- 90% 蟹卫召唤：弦月（微光、低理智光环）
        SHELL_LEVEL = 3, -- 75% 贝壳环：半月
        SNARE_LEVEL = 4, -- 50% 海带骨刺：月盈月亏
        FINAL_LEVEL = 5, -- 30% 最终阶段：满月（全亮、理智光环最高）
    },

    FINAL_PHASE =
    {
        PHASE_HEALTH = 0.3,

        -- 房屋沿用 Boss 剩余生命，避免阶段切换时凭空恢复生命。
        HOUSE_MIN_HEALTH = 100,

        -- 房子头顶血条（原版 healthbar 组件）的显示参数
        HOUSE_HEALTHBAR_HEIGHT = 5,
        HOUSE_HEALTHBAR_WIDTH = 100,

        -- 最终阶段：从三个裂隙处召唤 1 蟹骑士 + 2 蟹卫
        --（裂隙位置 = 90% 时打开的原版堵住裂缝，奶奶岛固定 3 个）。
        FINAL_KNIGHT_COUNT = 1,    -- 蟹骑士数量（生成在第一个裂隙处）
        FINAL_GUARD_COUNT = 2,     -- 蟹卫数量（生成在其余裂隙处）
        -- 裂隙不足时的兜底生成参数（围绕房子找可通过点补足）
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
