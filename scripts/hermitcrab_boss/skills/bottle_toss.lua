-- ============================================================================
-- 一阶段瓶子投掷技能：100% ~ 75% 期间，Boss 手持漂流瓶、保持距离远程投瓶。
--
-- 触发机制：复用 combat 组件的攻击周期（doattack 事件）。
--   - 一阶段把 combat range 调到 14~18，ChaseAndAttack 会把 Boss 带到投瓶
--     距离（而非贴脸），attack period 到点后 push "doattack"，SG 进入
--     bottle_attack 状态播放 throw 动画，第 7 帧调用 inst:ThrowBottleAt()。
--   - 75% 进入三叉戟阶段（SHELL_PHASE）后切回近战，恢复原行为。
-- ============================================================================

local events = require("hermitcrab_boss/events")
local bottle_bombard = require("hermitcrab_boss/bottle_bombard")
local tuning = require("hermitcrab_boss/tuning")

local BottleToss =
{
    PREFABS =
    {
        "messagebottle_throwable",
    },
}

-- 一阶段投瓶参数（70% 伤害与基础近战一致，避免一阶段过强）。
local BOTTLE = tuning.BOTTLE_TOSS

-- 从目标玩家当前位置生成落点（玩家位置 + 随机小抖动，逼玩家持续移动）。
local function CollectAim(target)
    if target == nil or not target:IsValid() then
        return nil
    end

    local pos = target:GetPosition()
    local angle = math.random() * TWOPI
    local jitter = math.random() * BOTTLE.AIM_JITTER
    return
    {
        x = pos.x + math.cos(angle) * jitter,
        z = pos.z - math.sin(angle) * jitter,
    }
end

-- SG bottle_attack 状态第 7 帧调用：向目标玩家脚下抛一个瓶子。
local function ThrowBottleAt(inst, target)
    if not inst._bottle_mode
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    local aim = CollectAim(target)
    if aim == nil then
        return
    end

    bottle_bombard.Throw(
        inst, -- thrower = Boss
        inst, -- attacker = Boss（伤害归属）
        aim,
        {
            damage = BOTTLE.DAMAGE,
            radius = BOTTLE.DAMAGE_RADIUS,
            speed = BOTTLE.SPEED,
            launch_height = BOTTLE.LAUNCH_HEIGHT,
            explode_fx = BOTTLE.EXPLODE_FX,
        },
        "_bottle_toss_guids"
    )
end

-- 退出瓶子模式：切回三叉戟近战（75% 阶段 / 最终阶段 / 战斗结束）。
local function ExitBottleMode(inst)
    if not inst._bottle_mode then
        return
    end

    inst._bottle_mode = false
    if inst.components.combat ~= nil then
        inst.components.combat:SetRange(BOTTLE.MELEE_ATTACK_RANGE, BOTTLE.MELEE_HIT_RANGE)
        inst.components.combat:SetAttackPeriod(tuning.ATTACK_PERIOD)
    end
    bottle_bombard.CleanupGuids(inst, "_bottle_toss_guids")
end

local function OnShellPhase(inst)
    ExitBottleMode(inst)
end

local function OnFinalPhase(inst)
    ExitBottleMode(inst)
end

local function OnEncounterFinished(inst)
    ExitBottleMode(inst)
end

function BottleToss.Attach(inst)
    inst._bottle_mode = true
    inst.ThrowBottleAt = ThrowBottleAt

    -- 一阶段战斗配置：远程投瓶（覆盖 ConfigureServerComponents 的近战 range）。
    if inst.components.combat ~= nil then
        inst.components.combat:SetRange(BOTTLE.ATTACK_RANGE, BOTTLE.HIT_RANGE)
        inst.components.combat:SetAttackPeriod(BOTTLE.ATTACK_PERIOD)
    end

    inst:ListenForEvent(events.SHELL_PHASE, OnShellPhase)
    inst:ListenForEvent(events.FINAL_PHASE_STARTED, OnFinalPhase)
    inst:ListenForEvent(events.ENCOUNTER_FINISHED, OnEncounterFinished)
end

return BottleToss
