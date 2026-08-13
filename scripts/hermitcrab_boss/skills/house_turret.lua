-- 30% 血量阶段：寄居蟹隐士退入小屋，小屋化身炮塔。
-- 攻击手段混用原版两种激光（线条形：以小屋为原点向目标排成一串爆炸点，
--   原版巨鹿激光扫射同款，共享 targets/skiptoss 避免同一目标吃多次伤害）：
--   deerclops_laser     —— 冬季盛宴·巨鹿激光（红）
--   alterguardian_laser —— 天体英雄·月灵激光（蓝）
-- 以及 wagboss_missile 追踪导弹，优先锁定热源（星星/高温暖石）。
--
-- 进出屋动画使用原版寄居蟹 gohome 的 give 动画（第 5 帧定格）。
local tuning = require("hermitcrab_boss/tuning").HOUSE_TURRET

local HouseTurret = {}

local HOUSE_TAGS = { "hermithouse" }

local PLAYER_MUST_TAGS = { "player" }
local PLAYER_CANT_TAGS = { "playerghost", "INLIMBO" }

local HEAT_MUST_TAGS = { "heatstar", "heatrock" }

local BEAM_PREFABS = { "deerclops_laser", "alterguardian_laser" }

-- 与激光同色系的烟雾拖尾，用于填充光线上的空隙
local TRAIL_PREFABS =
{
    deerclops_laser     = "deerclops_lasertrail",
    alterguardian_laser = "alterguardian_lasertrail",
}

-- ======================= 位置 =======================
-- 以小屋为中心发射（小屋被拆/找不到时退回 Boss 当前位置）。
local function GetTurretPosition(inst)
    local house = inst._turret_house
    if house ~= nil and house:IsValid() then
        return house.Transform:GetWorldPosition()
    end
    return inst.Transform:GetWorldPosition()
end

local function FindHouse(inst)
    return FindEntity(inst, tuning.HOUSE_SEARCH_RANGE, nil, HOUSE_TAGS)
end

-- 在小屋四周找一个可通行的“门口”落点（传送进屋 / 出屋复位用）。
local function GetTurretDoorPoint(house)
    local x, _, z = house.Transform:GetWorldPosition()
    for _, angle in ipairs({ 0, 90, 180, 270 }) do
        local rad = angle * DEGREES
        for radius = 2, 5 do
            local px = x + radius * math.cos(rad)
            local pz = z - radius * math.sin(rad)
            if TheWorld.Map:IsPassableAtPoint(px, 0, pz) then
                return Vector3(px, 0, pz)
            end
        end
    end
    return Vector3(x, 0, z)
end

-- ======================= 激光 =======================
-- 线条形激光：以小屋为原点，向目标方向排成一串爆炸点（原版巨鹿扫射同款），
-- 相邻点之间补同色烟雾拖尾让光线更连续；递增延迟形成由近及远的扫射。
-- 共享 targets/skiptoss 表：同一目标只被最先命中的那段打一次，避免秒杀。
-- 不指定 caster，直接改写激光自身的 defaultdamage，避免污染 Boss 的攻击力。
local function SpawnLaserTrails(beam_name, x, z, dx, dz)
    local trail_name = TRAIL_PREFABS[beam_name]
    for s = 0, tuning.LASER_STEPS - 1 do
        local mid = (s + 0.5) / tuning.LASER_STEPS
        local fx = SpawnPrefab(trail_name)
        if fx ~= nil then
            fx.Transform:SetPosition(x + dx * mid, 0, z + dz * mid)
            fx:FastForward(GetRandomMinMax(0.3, 0.7))
        end
    end
end

local function FireLaser(inst)
    local x, _, z = GetTurretPosition(inst)
    local targets = TheSim:FindEntities(x, 0, z, tuning.ATTACK_RANGE, PLAYER_MUST_TAGS, PLAYER_CANT_TAGS)
    if #targets == 0 then
        return
    end

    -- 每轮红蓝激光交替，各形成一条从房屋射向玩家的光线
    for i = 1, tuning.LASER_COUNT do
        local target = targets[math.random(#targets)]
        if target ~= nil and target:IsValid() then
            local tx, _, tz = target.Transform:GetWorldPosition()
            local dx, dz = tx - x, tz - z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist >= 1 then
                local beam_name = BEAM_PREFABS[(i - 1) % #BEAM_PREFABS + 1]
                SpawnLaserTrails(beam_name, x, z, dx, dz)

                local shared_targets, shared_skiptoss = {}, {}
                for s = 1, tuning.LASER_STEPS do
                    local t = s / tuning.LASER_STEPS
                    local beam = SpawnPrefab(beam_name)
                    if beam ~= nil then
                        beam.Transform:SetPosition(x + dx * t, 0, z + dz * t)
                        beam.components.combat:SetDefaultDamage(tuning.LASER_DAMAGE)
                        if beam_name == "alterguardian_laser" then
                            -- skipscorch：蓝色激光不烧焦地面
                            beam:Trigger(s * 2 * FRAMES, shared_targets, shared_skiptoss, true)
                        else
                            beam:Trigger(s * 2 * FRAMES, shared_targets, shared_skiptoss)
                        end
                    end
                end
            end
        end
    end
end

-- ======================= 追踪导弹 =======================
-- 优先锁定热源（星星/高温暖石，取最近），没有热源才随机打玩家。
-- wagboss_missile 的 Detonate 自带熄灭星星、消耗暖石热量的逻辑。
local function FindMissileTarget(inst, x, z)
    local best, bestsq = nil, nil
    for _, heat in ipairs(TheSim:FindEntities(x, 0, z, tuning.HEAT_SCAN_RANGE, nil, nil, HEAT_MUST_TAGS)) do
        if heat:IsValid() and not heat:IsInLimbo() then
            local hx, _, hz = heat.Transform:GetWorldPosition()
            local dsq = (hx - x) * (hx - x) + (hz - z) * (hz - z)
            if bestsq == nil or dsq < bestsq then
                best, bestsq = heat, dsq
            end
        end
    end
    if best ~= nil then
        return best
    end

    local players = TheSim:FindEntities(x, 0, z, tuning.ATTACK_RANGE, PLAYER_MUST_TAGS, PLAYER_CANT_TAGS)
    if #players > 0 then
        return players[math.random(#players)]
    end
    return nil
end

local function FireMissile(inst)
    local x, _, z = GetTurretPosition(inst)
    local grouptargets = {}

    for i = 1, tuning.MISSILE_COUNT do
        local target = FindMissileTarget(inst, x, z)
        if target ~= nil then
            local missile = SpawnPrefab("wagboss_missile")
            if missile ~= nil then
                missile.components.combat:SetDefaultDamage(tuning.MISSILE_DAMAGE)
                missile:Launch(i, inst, target, math.random(0, 360), grouptargets)
                missile:ShowMissile()
            end
        end
    end
end

-- ======================= 进屋 / 出屋 =======================
local function EnterHouse(inst)
    if inst._turret_phase_active then
        return
    end
    inst._turret_phase_active = true

    inst.components.combat:SetTarget(nil)
    inst.components.combat:CancelAttack()
    inst.components.locomotor:StopMoving()
    inst.Physics:Stop()

    inst:Hide()
    inst.Physics:SetCollides(false)

    inst.components.health:SetInvincible(true)

    -- 炮塔开火：激光 + 导弹两条独立周期
    inst._turret_laser_task = inst:DoPeriodicTask(tuning.LASER_INTERVAL, FireLaser, tuning.LASER_INTERVAL)
    inst._turret_missile_task = inst:DoPeriodicTask(tuning.MISSILE_INTERVAL, FireMissile, tuning.MISSILE_INTERVAL)
end

local function ExitHouse(inst)
    if not inst._turret_phase_active then
        return
    end
    inst._turret_phase_active = nil

    if inst._turret_laser_task ~= nil then
        inst._turret_laser_task:Cancel()
        inst._turret_laser_task = nil
    end
    if inst._turret_missile_task ~= nil then
        inst._turret_missile_task:Cancel()
        inst._turret_missile_task = nil
    end

    -- 回到进屋时的门口位置（无则原地现身）
    local door = inst._turret_door
    if door ~= nil then
        inst.Physics:SetCollides(false)
        inst.Physics:Teleport(door.x, 0, door.z)
        inst.Physics:SetCollides(true)
    end

    inst:Show()
    inst.Physics:SetCollides(true)
    inst.components.health:SetInvincible(false)
    inst.components.locomotor:StopMoving()
    inst.Physics:Stop()
end

-- ======================= 走向小屋 =======================
-- 用物理马达速度直接驱动行走（不经由 locomotor），
-- 避免 OnLocomote 把状态切回 CommonStates 的 walk 状态导致到达检测失效。
local function StopTurretApproach(inst)
    if inst._turret_approach_task ~= nil then
        inst._turret_approach_task:Cancel()
        inst._turret_approach_task = nil
    end
end

local function UpdateTurretApproach(inst)
    if inst._turret_phase_active then
        StopTurretApproach(inst)
        return
    end

    local house = inst._turret_house
    if house == nil or not house:IsValid() then
        -- 小屋没了：原地进屋兜底
        StopTurretApproach(inst)
        inst:EnterHouse()
        if inst.sg ~= nil then
            inst.sg:GoToState("turret_active")
        end
        return
    end

    if inst:IsNear(house, 2.5) then
        -- 走到门口 → 播放 gohome 动画
        StopTurretApproach(inst)
        if inst.sg ~= nil then
            inst.sg:GoToState("turret_enter")
        end
        return
    end

    local hx, _, hz = house.Transform:GetWorldPosition()
    local x, _, z = inst.Transform:GetWorldPosition()
    local dist = math.sqrt((hx - x) * (hx - x) + (hz - z) * (hz - z))
    if dist > 0.1 then
        local speed = inst.components.locomotor.walkspeed
        inst:ForceFacePoint(hx, 0, hz)
        inst.Physics:SetMotorVel((hx - x) / dist * speed, 0, (hz - z) / dist * speed)
    end
end

local function StartTurretApproach(inst, house)
    StopTurretApproach(inst)
    inst._turret_house = house
    inst._turret_approach_task = inst:DoPeriodicTask(0.25, UpdateTurretApproach, 0)
end

-- ======================= 兜底清理 =======================
local function OnEncounterFinished(inst)
    StopTurretApproach(inst)
    if inst._turret_phase_active then
        ExitHouse(inst)
    end
    inst._turret_phase_triggered = nil
    inst._turret_house = nil
    inst._turret_door = nil
    inst.components.health:SetInvincible(false)
end

local function Begin(inst)
    if inst._turret_phase_triggered or inst._encounter_resolved or inst._surrendering then
        return
    end

    inst._turret_phase_triggered = true
    inst.components.combat:CancelAttack()
    inst:PushEvent("hermitboss_house_turret")
end

local function OnHealthDelta(inst, data)
    if not inst._turret_phase_triggered
        and not inst._surrendering
        and not inst._encounter_resolved
        and inst.components.health.currenthealth > inst.components.health.minhealth
        and data ~= nil
        and data.oldpercent > tuning.PHASE_HEALTH
        and data.newpercent <= tuning.PHASE_HEALTH then
        Begin(inst)
    end
end

function HouseTurret.Attach(inst, encounter_finished_event)
    inst.FindTurretHouse = FindHouse
    inst.GetTurretDoorPoint = GetTurretDoorPoint
    inst.EnterHouse = EnterHouse
    inst.ExitHouse = ExitHouse
    inst.StartTurretApproach = StartTurretApproach
    inst.StopTurretApproach = StopTurretApproach

    inst:ListenForEvent("healthdelta", OnHealthDelta)
    inst:ListenForEvent(encounter_finished_event, OnEncounterFinished)
end

return HouseTurret
