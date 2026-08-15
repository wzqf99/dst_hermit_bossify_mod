-- 本场 Boss 战专用的环绕贝壳堆。
-- 只复用原版 shell_cluster 外观，不带采矿、掉落或水下打捞逻辑。

local tuning = require("hermitcrab_boss/tuning").SHELL_RING

local assets =
{
    Asset("ANIM", "anim/singingshell_cluster.zip"),
}

local prefabs =
{
    "rock_break_fx",
    "singingshell_octave3",
    "singingshell_octave4",
    "singingshell_octave5",
}

local LAUNCH_DURATION = 1.25
local LAUNCH_HEIGHT = 7
local ORBIT_RADIUS = 4.5
local ORBIT_HEIGHT = 0.8
local ORBIT_BOB_HEIGHT = 0.18
local ORBIT_ANGULAR_SPEED = 0.55
local UPDATE_PERIOD = FRAMES
local MAX_FOLLOW_DISTANCE = 8
local CONTACT_RADIUS = 0.75 -- 与原版 shell_cluster 的碰撞半径一致
local CONTACT_CHECK_PERIOD = 0.1
local BASE_SCALE = 0.6
local BASE_SHADOW_WIDTH = 1.15
local BASE_SHADOW_HEIGHT = 0.5

-- 六枚贝壳使用不同但有界的视觉参数。轨道角速度保持一致，避免长时间战斗后聚成一团。
local VISUAL_VARIATIONS =
{
    { scale = 0.55, radius = -0.30, height = -0.08, bob = 0.85, phase = 0.2, wobble = 0.035, wobble_speed = 1.10, radial_speed = 0.80, spin = -8, follow = 9.0 },
    { scale = 0.58, radius =  0.18, height =  0.10, bob = 1.10, phase = 1.3, wobble = 0.025, wobble_speed = 0.85, radial_speed = 1.05, spin =  6, follow = 8.2 },
    { scale = 0.62, radius = -0.08, height =  0.02, bob = 0.95, phase = 2.5, wobble = 0.040, wobble_speed = 1.25, radial_speed = 0.90, spin = -5, follow = 9.8 },
    { scale = 0.57, radius =  0.34, height = -0.03, bob = 1.20, phase = 3.6, wobble = 0.030, wobble_speed = 0.95, radial_speed = 1.15, spin =  9, follow = 8.7 },
    { scale = 0.64, radius = -0.20, height =  0.12, bob = 0.90, phase = 4.7, wobble = 0.020, wobble_speed = 1.35, radial_speed = 0.85, spin = -7, follow = 9.4 },
    { scale = 0.60, radius =  0.06, height = -0.12, bob = 1.15, phase = 5.8, wobble = 0.045, wobble_speed = 1.05, radial_speed = 1.10, spin =  5, follow = 8.5 },
}

local TARGET_CANT_TAGS = { "playerghost", "INLIMBO", "FX", "DECOR", "crabking_ally", "hermithouse" }
local TARGET_ONEOF_TAGS = { "_combat", "HAMMER_workable" }
local SINGING_SHELL_PREFABS =
{
    "singingshell_octave3",
    "singingshell_octave4",
    "singingshell_octave5",
}

local function ApplyVisualVariation(inst)
    local index = inst._visual_variant:value()
    local variation = VISUAL_VARIATIONS[index] or VISUAL_VARIATIONS[1]
    local shadow_scale = variation.scale / BASE_SCALE

    inst._visual_data = variation
    inst._contact_radius = CONTACT_RADIUS * shadow_scale
    inst:SetPhysicsRadiusOverride(inst._contact_radius)
    inst.Transform:SetScale(variation.scale, variation.scale, variation.scale)
    inst.DynamicShadow:SetSize(
        BASE_SHADOW_WIDTH * shadow_scale,
        BASE_SHADOW_HEIGHT * shadow_scale
    )
end

local function RemoveOwnerListener(inst)
    if inst._boss ~= nil and inst._on_boss_removed ~= nil then
        inst:RemoveEventCallback("onremove", inst._on_boss_removed, inst._boss)
    end
    inst._on_boss_removed = nil
    inst._boss = nil
end

local function OnRemoveEntity(inst)
    RemoveOwnerListener(inst)
    if inst._move_task ~= nil then
        inst._move_task:Cancel()
        inst._move_task = nil
    end
end

local function BreakShell(inst)
    if inst._breaking then
        return
    end

    inst._breaking = true
    local x, _, z = inst.Transform:GetWorldPosition()
    local drop_position = Vector3(x, 0, z)
    local fx = SpawnPrefab("rock_break_fx")
    if fx ~= nil then
        fx.Transform:SetPosition(drop_position:Get())
    end

    for _ = 1, math.random(1, 3) do
        inst.components.lootdropper:SpawnLootPrefab(
            SINGING_SHELL_PREFABS[math.random(#SINGING_SHELL_PREFABS)],
            drop_position
        )
    end
    inst:Remove()
end

-- 切换环绕锚点（最终阶段从 Boss 切到房屋）。
-- 切换时把跟随插值位置重置到当前坐标，避免长距离跳变。
local function SetOrbitAnchor(inst, anchor)
    if anchor == nil or not anchor:IsValid() or anchor == inst._anchor then
        return
    end

    inst._anchor = anchor
    local x, _, z = inst.Transform:GetWorldPosition()
    inst._follow_x = x
    inst._follow_z = z
end

local function RecordContact(inst)
    inst._contact_count = inst._contact_count + 1
    if inst._contact_count >= tuning.MAX_CONTACTS then
        BreakShell(inst)
        return true
    end

    return false
end

local function IsDestructibleStructure(target)
    local workable = target.components.workable
    return workable ~= nil
        and workable:CanBeWorked()
        and workable:GetWorkAction() == ACTIONS.HAMMER
        and (target:HasTag("wall") or target:HasTag("structure"))
end

local function HandleNewContact(inst, target)
    local boss = inst._boss
    -- 环绕锚点（最终阶段为房屋）不算可接触目标，防止贝壳把房屋撞毁。
    if target == boss or target == inst._anchor then
        return false
    end

    -- 墙也有战斗组件，因此必须先按建筑处理。
    if IsDestructibleStructure(target) then
        if boss ~= nil then
            target.components.workable:Destroy(boss)
        end
    elseif boss == nil
        or boss.TryShellContactHit == nil
        or not boss:TryShellContactHit(inst, target) then
        return false
    end

    return RecordContact(inst)
end

local function CheckContacts(inst, x, z, now)
    if now < inst._next_contact_check then
        return
    end
    inst._next_contact_check = now + CONTACT_CHECK_PERIOD

    local contact_radius = inst._contact_radius or CONTACT_RADIUS
    local current_contacts = {}

    for _, target in ipairs(TheSim:FindEntities(
        x,
        0,
        z,
        contact_radius + 3,
        nil,
        TARGET_CANT_TAGS,
        TARGET_ONEOF_TAGS
    )) do
        local radius = contact_radius + target:GetPhysicsRadius(0)
        local target_x, _, target_z = target.Transform:GetWorldPosition()
        local dx = target_x - x
        local dz = target_z - z
        if dx * dx + dz * dz <= radius * radius then
            current_contacts[target] = true
            if not inst._contacts[target]
                and HandleNewContact(inst, target) then
                return true
            end
        end
    end

    -- 目标离开判定范围后，下一次进入才会算作新的碰撞。
    inst._contacts = current_contacts
    return false
end

local function UpdatePosition(inst)
    local boss = inst._boss
    if boss == nil or not boss:IsValid() or boss._encounter_resolved then
        BreakShell(inst)
        return
    end

    -- 最终阶段：把轨道中心从 Boss 切到房屋。
    -- 房屋引用（boss._final_house）出现即生效，不依赖事件时序。
    if inst._anchor == boss and boss._final_phase_triggered then
        local house = boss._final_house
        if house ~= nil and house:IsValid() then
            SetOrbitAnchor(inst, house)
        end
    end

    local anchor = inst._anchor
    if anchor == nil or not anchor:IsValid() then
        BreakShell(inst)
        return
    end

    local now = GetTime()
    local elapsed = now - inst._start_time
    local orbit_elapsed = math.max(0, elapsed - LAUNCH_DURATION)
    local variation = inst._visual_data or VISUAL_VARIATIONS[1]
    local angle = inst._base_angle
        + orbit_elapsed * ORBIT_ANGULAR_SPEED
        + variation.wobble * math.sin(orbit_elapsed * variation.wobble_speed + variation.phase)
    local boss_x, boss_y, boss_z = anchor.Transform:GetWorldPosition()
    local orbit_radius = ORBIT_RADIUS
        + variation.radius
        + 0.1 * math.sin(orbit_elapsed * variation.radial_speed + variation.phase)
    local target_x = boss_x + orbit_radius * math.cos(angle)
    local target_z = boss_z - orbit_radius * math.sin(angle)
    local target_y = boss_y + ORBIT_HEIGHT + variation.height
        + ORBIT_BOB_HEIGHT * variation.bob
            * math.sin(orbit_elapsed * 3 + inst._base_angle + variation.phase)

    if elapsed < LAUNCH_DURATION then
        local progress = math.max(0, elapsed / LAUNCH_DURATION)
        local eased = progress * progress * (3 - 2 * progress)
        local arc = math.sin(progress * PI) * LAUNCH_HEIGHT
        inst.Transform:SetPosition(
            inst._start_x + (target_x - inst._start_x) * eased,
            inst._start_y + (target_y - inst._start_y) * eased + arc,
            inst._start_z + (target_z - inst._start_z) * eased
        )
    else
        local current_x, _, current_z = inst.Transform:GetWorldPosition()
        inst._follow_x = inst._follow_x or current_x
        inst._follow_z = inst._follow_z or current_z

        local follow_dx = target_x - inst._follow_x
        local follow_dz = target_z - inst._follow_z
        if follow_dx * follow_dx + follow_dz * follow_dz > MAX_FOLLOW_DISTANCE * MAX_FOLLOW_DISTANCE then
            inst._follow_x = target_x
            inst._follow_z = target_z
        else
            local dt = math.min(now - (inst._last_update_time or now - UPDATE_PERIOD), 0.25)
            local follow_alpha = 1 - math.exp(-variation.follow * dt)
            inst._follow_x = inst._follow_x + follow_dx * follow_alpha
            inst._follow_z = inst._follow_z + follow_dz * follow_alpha
        end

        inst.Transform:SetPosition(inst._follow_x, target_y, inst._follow_z)
        if CheckContacts(inst, inst._follow_x, inst._follow_z, now) then
            return
        end
    end

    inst._last_update_time = now
    inst.Transform:SetRotation(
        angle * RADIANS + 90 + orbit_elapsed * variation.spin
    )
end

local function SetBoss(inst, boss, index, count, start_angle)
    if inst._boss ~= nil or boss == nil or not boss:IsValid() then
        return
    end

    inst._boss = boss
    inst._anchor = boss
    inst._base_angle = start_angle + (index - 1) * TWOPI / count
    inst._start_time = GetTime()
    inst._next_contact_check = inst._start_time
    inst._contact_count = 0
    inst._contacts = {}
    inst._start_x, inst._start_y, inst._start_z = inst.Transform:GetWorldPosition()

    local variation_offset = math.floor(start_angle / TWOPI * #VISUAL_VARIATIONS)
    inst._visual_variant:set((index + variation_offset - 1) % #VISUAL_VARIATIONS + 1)
    ApplyVisualVariation(inst)

    inst._on_boss_removed = function()
        if inst:IsValid() then
            BreakShell(inst)
        end
    end
    inst:ListenForEvent("onremove", inst._on_boss_removed, boss)

    inst._move_task = inst:DoPeriodicTask(UPDATE_PERIOD, UpdatePosition, 0)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    inst:SetPhysicsRadiusOverride(CONTACT_RADIUS)
    inst.AnimState:SetBank("singingshell_cluster")
    inst.AnimState:SetBuild("singingshell_cluster")
    inst.AnimState:PlayAnimation("idle", true)

    inst._visual_variant = net_tinybyte(
        inst.GUID,
        "hermitcrab_boss_shell.visual_variant",
        "visualvariantdirty"
    )
    inst:ListenForEvent("visualvariantdirty", ApplyVisualVariation)
    ApplyVisualVariation(inst)

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")
    inst:AddTag("notarget")
    inst:AddTag("hermitcrab_boss_shell")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.entity:SetCanSleep(false)
    inst.persists = false

    inst:AddComponent("lootdropper")

    inst.SetBoss = SetBoss
    inst.SetOrbitAnchor = SetOrbitAnchor
    inst.BreakShell = BreakShell
    inst.OnRemoveEntity = OnRemoveEntity

    return inst
end

return Prefab("hermitcrab_boss_shell", fn, assets, prefabs)
