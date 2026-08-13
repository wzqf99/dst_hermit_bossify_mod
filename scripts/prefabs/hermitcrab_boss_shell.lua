-- 本场 Boss 战专用的环绕贝壳堆。
-- 只复用原版 shell_cluster 外观，不带采矿、掉落或水下打捞逻辑。

local assets =
{
    Asset("ANIM", "anim/singingshell_cluster.zip"),
}

local LAUNCH_DURATION = 1.25
local LAUNCH_HEIGHT = 7
local ORBIT_RADIUS = 4.5
local ORBIT_HEIGHT = 0.8
local ORBIT_BOB_HEIGHT = 0.18
local ORBIT_ANGULAR_SPEED = 0.55
local UPDATE_PERIOD = FRAMES
local CONTACT_RADIUS = 0.75 -- 与原版 shell_cluster 的碰撞半径一致
local CONTACT_CHECK_PERIOD = 0.1

local TARGET_MUST_TAGS = { "player" }
local TARGET_CANT_TAGS = { "playerghost", "INLIMBO" }

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

local function CheckContactDamage(inst, x, z, now)
    if now < inst._next_contact_check then
        return
    end
    inst._next_contact_check = now + CONTACT_CHECK_PERIOD

    local boss = inst._boss
    if boss.TryShellContactHit == nil then
        return
    end

    for _, target in ipairs(TheSim:FindEntities(
        x,
        0,
        z,
        CONTACT_RADIUS + 1,
        TARGET_MUST_TAGS,
        TARGET_CANT_TAGS
    )) do
        local radius = CONTACT_RADIUS + target:GetPhysicsRadius(0)
        local target_x, _, target_z = target.Transform:GetWorldPosition()
        local dx = target_x - x
        local dz = target_z - z
        if dx * dx + dz * dz <= radius * radius then
            boss:TryShellContactHit(inst, target)
        end
    end
end

local function UpdatePosition(inst)
    local boss = inst._boss
    if boss == nil or not boss:IsValid() or boss._encounter_resolved then
        inst:Remove()
        return
    end

    local now = GetTime()
    local elapsed = now - inst._start_time
    local orbit_elapsed = math.max(0, elapsed - LAUNCH_DURATION)
    local angle = inst._base_angle + orbit_elapsed * ORBIT_ANGULAR_SPEED
    local boss_x, boss_y, boss_z = boss.Transform:GetWorldPosition()
    local target_x = boss_x + ORBIT_RADIUS * math.cos(angle)
    local target_z = boss_z - ORBIT_RADIUS * math.sin(angle)
    local target_y = boss_y + ORBIT_HEIGHT
        + ORBIT_BOB_HEIGHT * math.sin(orbit_elapsed * 3 + inst._base_angle)

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
        inst.Transform:SetPosition(target_x, target_y, target_z)
        CheckContactDamage(inst, target_x, target_z, now)
    end

    inst.Transform:SetRotation(angle * RADIANS + 90)
end

local function SetBoss(inst, boss, index, count, start_angle)
    if inst._boss ~= nil or boss == nil or not boss:IsValid() then
        return
    end

    inst._boss = boss
    inst._base_angle = start_angle + (index - 1) * TWOPI / count
    inst._start_time = GetTime()
    inst._next_contact_check = inst._start_time
    inst._start_x, inst._start_y, inst._start_z = inst.Transform:GetWorldPosition()

    inst._on_boss_removed = function()
        if inst:IsValid() then
            inst:Remove()
        end
    end
    inst:ListenForEvent("onremove", inst._on_boss_removed, boss)

    inst._move_task = inst:DoPeriodicTask(UPDATE_PERIOD, UpdatePosition, 0)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.Transform:SetScale(0.6, 0.6, 0.6)
    inst:SetPhysicsRadiusOverride(CONTACT_RADIUS)
    inst.AnimState:SetBank("singingshell_cluster")
    inst.AnimState:SetBuild("singingshell_cluster")
    inst.AnimState:PlayAnimation("idle", true)

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

    inst.SetBoss = SetBoss
    inst.OnRemoveEntity = OnRemoveEntity

    return inst
end

return Prefab("hermitcrab_boss_shell", fn, assets)
