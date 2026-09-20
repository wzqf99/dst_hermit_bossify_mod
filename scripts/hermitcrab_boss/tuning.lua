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

    -- ------------------------------------------------------------------
    -- 战斗胜利后的帝王蟹水面演出。
    --
    -- 位置推导：
    --   奶奶岛的陆地块定义在 map/static_layouts/hermitcrab_01.lua，其
    --   hermitcrab_marker 由 hermitcrab_relocation_manager 放在岛屿几何
    --   中心（原文注释：Place at island center, achievement marker for
    --   island center point）。也就是说 marker 一定在陆地正中，不是海面。
    --
    --   因此演出点不能直接用 marker，要沿固定方向向外找一个真正的海面点。
    --   岛屿近似正方形，半边长约 18 格，所以搜索距离上限要明显大于它。
    --   搜索按固定步长推进、命中即停，保证每次位置一致可预期。
    -- ------------------------------------------------------------------
    VICTORY_EPILOGUE =
    {
        -- 台词与节奏
        LINE_COUNT = 3,             -- 台词条数（对应 STRINGS.CRABKING_EPILOGUE_TALK）
        POST_TALK_DELAY = 0.5,      -- 最后一句说完到开始下沉的停顿（秒）
        LINE_INTERVAL = 3.4,        -- 每句台词的间隔（秒）
        DIALOGUE_DELAY = 0.35,      -- 出水动画结束到第一句台词的停顿（秒）

        -- 动画兜底超时（秒）：万一 animover 没到，也能继续流程。
        REAPPEAR_FALLBACK = 4,
        DISAPPEAR_FALLBACK = 4,

        -- 海面搜索：从岛屿中心沿该方向向外推进，找到第一个海面点为止。
        --
        -- 角度约定与原版 brain 一致（见 brains/pollyrogerbrain.lua）：
        --   x = dist * cos(角度)，z = dist * sin(角度)。
        -- 在 DST 世界坐标里 +x 向右、+z 向上（屏幕），因此：
        --   0        = 正右（东）
        --   PI/2     = 正上（北）
        --   -PI/2    = 正下（南）   <- 默认朝南出海
        --   PI       = 正左（西）
        OCEAN_SEARCH_ANGLE = -math.pi / 2,
        OCEAN_SEARCH_START = 8,     -- 起始搜索距离（格）
        OCEAN_SEARCH_STEP = 2,      -- 每次推进距离（格）
        OCEAN_SEARCH_MAX = 60,      -- 最大搜索距离（格），超过则放弃演出
        OCEAN_SEARCH_SPREAD = 0.5,  -- 主方向失败时两侧的偏转角（弧度，约 29°）

        -- 外观：与原版帝王蟹一致（CRABKING_SCALE = .7）
        SCALE = 0.7,
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

    -- 贝壳聚拢轰炸：75% 贝壳环首次召唤后，每 REPEAT_INTERVAL 秒释放一次。
    -- 技能流程 ORBIT → GATHER → SPIN → THROW → RETURN → ORBIT：
    -- 环绕贝壳脱离轨道，聚拢到 Boss 头顶高速旋转蓄力，再砸向玩家落点。
    SHELL_BOMBARD =
    {
        -- 首次贝壳环召唤后，每隔该秒数释放一次聚拢轰炸。
        REPEAT_INTERVAL = 15,

        -- 施法前摇：贝壳保持原轨道运行、Boss 播放施法动画的时长（秒）。
        CAST_DURATION = 1.0,

        -- 聚拢：贝壳从轨道位置飞向头顶的时长（秒）。
        GATHER_DURATION = 1.0,

        -- 旋转蓄力：贝壳在头顶高速旋转的时长（秒）。
        SPIN_DURATION = 1.2,

        -- 旋转蓄力期间的角速度（弧度/秒），需明显快于环绕角速度。
        SPIN_ANGULAR_SPEED = 6,

        -- 聚拢 / 旋转阶段贝壳相对头顶的高度（单位）。
        GATHER_HEIGHT = 3.5,

        -- 聚拢 / 旋转阶段的聚合半径（单位），略小于环绕半径。
        GATHER_RADIUS = 2.2,

        -- 投掷：贝壳从头顶砸向落点的飞行时长（秒）。
        THROW_DURATION = 0.6,

        -- 返回：落点飞回 Boss 环绕轨道的时长（秒）。
        RETURN_DURATION = 1.0,

        -- 落点预警：落点标记从出现到砸下的提前量（秒），给玩家走位空间。
        IMPACT_WARNING = 0.6,

        -- 落点半径：每枚贝壳落点相对玩家位置的散布半径（单位），
        -- 多玩家/多贝壳时让落点分散，避免完全重叠。
        IMPACT_SCATTER = 2.5,

        -- 落地伤害半径与伤害值。
        IMPACT_DAMAGE_RADIUS = 2.0,
        IMPACT_DAMAGE = BASE_DAMAGE,

        -- 落地击退：把落点范围内的玩家向外震开（增强砸地冲击力）。
        IMPACT_KNOCKBACK_STRENGTH = 1.0,   -- 击退力度倍率（shell_ring 接触为 0.45）

        -- 落地屏幕震动：命中玩家时震屏，营造重物砸地的重量感。
        -- 基于 DST 原生 camerashake prefab（落点附近震源），对客户端玩家自动生效。
        IMPACT_SHAKE_DURATION = 0.4,       -- 震屏持续时长（秒）
        IMPACT_SHAKE_SPEED = 0.6,          -- 震屏频率（Shake 第 4 个参数 / Frequency）
        IMPACT_SHAKE_SCALE = 0.8,          -- 震屏幅度（Shake 第 2 个参数 / Intensity）
        IMPACT_SHAKE_RADIUS = 12,          -- 震源影响半径

        -- 选择落点时玩家与 Boss 的最大距离。
        TARGET_RANGE = 40,
    },

    GUARD_SUMMON =
    {
        PHASE_HEALTH = 0.9,
        COUNT = 3,
        SPAWN_MIN_RADIUS = 2,
        SPAWN_MAX_RADIUS = 5,
        SPAWN_ATTEMPTS = 30,
    },

    -- 一阶段瓶子投掷：100% ~ 75% 期间，Boss 手持漂流瓶，保持距离远程投瓶。
    -- 复用 combat 攻击周期驱动（doattack → bottle_attack → throw 动画投瓶）。
    BOTTLE_TOSS =
    {
        -- 投瓶距离：KeepDistanceAndAttack 把 Boss 带/保持在 [RETREAT_DISTANCE, ATTACK_RANGE] 之间。
        ATTACK_RANGE = 14,
        HIT_RANGE = 18,

        -- 后退阈值：玩家距离小于该值时 Boss 后退，保持远程距离。
        RETREAT_DISTANCE = 9,

        -- 后退时是否跑步（true = 跑步后退，节奏更利落）。
        RETREAT_RUN = true,

        -- 后退步长：每次后退搜索可走点的距离（FindWalkableOffset 半径）。
        RETREAT_STEP = 6,

        -- 投瓶间隔（秒），即 combat 攻击周期。
        ATTACK_PERIOD = 3.5,

        -- 瓶子落地爆炸参数。
        DAMAGE = 40,
        DAMAGE_RADIUS = 2.5,
        SPEED = 12,
        LAUNCH_HEIGHT = 2.5,

        -- 落点相对玩家当前位置的抖动半径（逼玩家持续移动）。
        AIM_JITTER = 1.2,

        -- 落地爆炸特效（原版亮茄爆炸，与房屋阶段一致）。
        EXPLODE_FX = "bomb_lunarplant_explode_fx",

        -- 75% 切回近战后的恢复参数（与 ConfigureServerComponents 初始值一致）。
        MELEE_ATTACK_RANGE = 1.5,
        MELEE_HIT_RANGE = 2,
    },

    -- 堵住裂缝 Boss 战强化：随战斗阶段推进逐级"变大"（月相等级 1~5）。
    FISSURES =
    {
        OPEN_LEVEL  = 2, -- 90% 蟹卫召唤：弦月（微光、低理智光环）
        SHELL_LEVEL = 3, -- 75% 贝壳环：半月
        SNARE_LEVEL = 4, -- 50% 海带骨刺：月盈月亏
        FINAL_LEVEL = 5, -- 30% 最终阶段：满月（全亮、理智光环最高）
    },

    -- 奶奶身体周围的月亮氛围（与裂隙月相等级严格同步）。
    -- 随阶段逐级增强：发光渐亮 + 掉理智（天体侵蚀感）渐强。
    MOON_AURA =
    {
        -- 月光颜色（蓝白冷光，同原版月亮裂隙 moon_fissure）。
        COLOUR = { 130/255, 160/255, 170/255 },

        -- 各月相等级的 Light 参数与理智光环（索引 = 月相等级 1~5）。
        -- 1 初始(无光) 2 弦月(90%) 3 半月(75%) 4 月盈月亏(50%) 5 满月(30%)
        -- sanity 为负 = 掉理智。
        LEVELS =
        {
            { enabled = false, radius = 0.0,  intensity = 0.0, falloff = 1.0,  sanity = 0 },
            { enabled = true,  radius = 3.0,  intensity = 0.3, falloff = 2.25, sanity = -TUNING.SANITYAURA_TINY },
            { enabled = true,  radius = 6.0,  intensity = 0.4, falloff = 2.0,  sanity = -TUNING.SANITYAURA_SMALL },
            { enabled = true,  radius = 11.0, intensity = 0.5, falloff = 1.9,  sanity = -TUNING.SANITYAURA_MED },
            { enabled = true,  radius = 11.0, intensity = 0.5, falloff = 1.9,  sanity = -TUNING.SANITYAURA_LARGE },
        },

        -- 环绕天体粒子（飘浮的蓝色光点，原版 moon_altar_link_fx），随阶段增强频率。
        PARTICLE_PREFAB = "moon_altar_link_fx",
        PARTICLE_RADIUS = 1.6,      -- 环绕半径
        PARTICLE_HEIGHT_MIN = 0.4,  -- 粒子高度下限
        PARTICLE_HEIGHT_MAX = 2.0,  -- 粒子高度上限
        -- 各月相等级的粒子生成率（每秒光点数，索引 = 月相等级 1~5）。
        PARTICLE_RATE = { 0, 1.5, 2.5, 4, 6 },
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

        -- 房屋囚笼：进入房屋后，每隔一段时间在房屋一圈召唤海带刺牢笼
        --（复用 50% 海带刺 kelp_spike，伤害归属 Boss）。
        HOUSE_SNARE_INTERVAL = 10,   -- 召唤间隔（秒）
        HOUSE_SNARE_COUNT = 12,      -- 每圈海带刺数量
        HOUSE_SNARE_OFFSET = 2.5,    -- 距房屋边缘的偏移（半径 = 房屋物理半径 + 偏移）
    },
}
