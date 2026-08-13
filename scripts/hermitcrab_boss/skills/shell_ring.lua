local tuning = require("hermitcrab_boss/tuning").SHELL_RING

local ShellRing =
{
    PREFABS =
    {
        "crab_king_waterspout",
        "hermitcrab_boss_shell",
    },
}

local WATERSPOUT_DAMAGE = TUNING.TRIDENT.SPELL.DAMAGE
local WATERSPOUT_DAMAGE_RADIUS = TUNING.TRIDENT.SPELL.RADIUS

local PLAYER_MUST_TAGS = { "player" }
local PLAYER_CANT_TAGS = { "playerghost", "INLIMBO" }
local SUNKEN_SHELL_MUST_TAGS = { "underwater_salvageable" }

local function CanDamageTarget(inst, target)
    return target ~= nil
        and target:IsValid()
        and target ~= inst
        and target.components.combat ~= nil
        and target.components.health ~= nil
        and not target.components.health:IsDead()
        and not target:HasTag("wall")
        and not target:HasTag("structure")
        and inst.components.combat:CanTarget(target)
end

-- crab_king_waterspout 只是视觉特效，实际伤害由施法方处理。
local function DoWaterspoutDamage(inst, point, waterspout, hit_targets)
    local x, y, z = point:Get()
    for _, target in ipairs(TheSim:FindEntities(
        x,
        y,
        z,
        WATERSPOUT_DAMAGE_RADIUS + 1,
        PLAYER_MUST_TAGS,
        PLAYER_CANT_TAGS
    )) do
        local radius = WATERSPOUT_DAMAGE_RADIUS + target:GetPhysicsRadius(0)
        local target_x, _, target_z = target.Transform:GetWorldPosition()
        local dx = target_x - x
        local dz = target_z - z
        if not hit_targets[target]
            and dx * dx + dz * dz <= radius * radius
            and CanDamageTarget(inst, target) then
            if target.components.combat:GetAttacked(
                inst,
                WATERSPOUT_DAMAGE,
                waterspout
            ) then
                hit_targets[target] = true
            end
        end
    end
end

-- 六枚贝壳共用伤害冷却；冷却期间的新接触仍是有效碰撞。
local function TryContactHit(inst, shell, target)
    if inst._encounter_resolved
        or inst._surrendering
        or not CanDamageTarget(inst, target) then
        return false
    end

    local now = GetTime()
    inst._shell_hit_cooldowns = inst._shell_hit_cooldowns or {}
    if (inst._shell_hit_cooldowns[target] or 0) > now then
        return true
    end

    if target.components.combat:GetAttacked(inst, tuning.CONTACT_DAMAGE, shell) then
        inst._shell_hit_cooldowns[target] = now + tuning.CONTACT_COOLDOWN
        target:PushEvent("knockback", {
            knocker = shell,
            radius = shell:GetPhysicsRadius(0.75) + target:GetPhysicsRadius(0),
            strengthmult = 0.45,
            forcelanded = true,
        })
    end

    return true
end

local function IsFarEnoughFromWaterPoints(points, x, z)
    local min_distance_sq =
        tuning.WATER_POINT_MIN_SPACING * tuning.WATER_POINT_MIN_SPACING
    for _, point in ipairs(points) do
        local dx = point.x - x
        local dz = point.z - z
        if dx * dx + dz * dz < min_distance_sq then
            return false
        end
    end

    return true
end

local function TryAddWaterPoint(points, x, z)
    if TheWorld.Map:IsOceanAtPoint(x, 0, z, false)
        and IsFarEnoughFromWaterPoints(points, x, z) then
        table.insert(points, Vector3(x, 0, z))
        return true
    end

    return false
end

local function GetSunkenShellCluster(salvage)
    if salvage == nil
        or not salvage:IsValid()
        or salvage.components.winchtarget == nil then
        return nil
    end

    local shell_cluster = salvage.components.winchtarget:GetSunkenObject()
    return shell_cluster ~= nil
        and shell_cluster:IsValid()
        and shell_cluster.prefab == "shell_cluster"
        and shell_cluster
        or nil
end

-- 优先使用靠近 Boss 的真实水下贝壳堆，保证水柱和起飞过程可见。
local function FindSunkenShellClusters(inst)
    local center = inst._island_center or inst:GetPosition()
    local boss_x, _, boss_z = inst.Transform:GetWorldPosition()
    local sources = {}

    for _, salvage in ipairs(TheSim:FindEntities(
        center.x,
        0,
        center.z,
        tuning.SALVAGE_RADIUS,
        SUNKEN_SHELL_MUST_TAGS
    )) do
        local shell_cluster = GetSunkenShellCluster(salvage)
        if shell_cluster ~= nil then
            local x, _, z = salvage.Transform:GetWorldPosition()
            local dx = x - boss_x
            local dz = z - boss_z
            table.insert(sources, {
                salvage = salvage,
                shell_cluster = shell_cluster,
                point = Vector3(x, 0, z),
                distance_sq = dx * dx + dz * dz,
            })
        end
    end

    table.sort(sources, function(a, b)
        if a.distance_sq == b.distance_sq then
            return a.salvage.GUID < b.salvage.GUID
        end
        return a.distance_sq < b.distance_sq
    end)

    while #sources > tuning.COUNT do
        table.remove(sources)
    end

    return sources
end

local function ConsumeSunkenShellCluster(inst, source)
    local salvage = source.salvage
    local shell_cluster = GetSunkenShellCluster(salvage)
    if shell_cluster == nil or shell_cluster ~= source.shell_cluster then
        return false
    end

    local inventory = salvage.components.inventory
    if inventory == nil
        or inventory:RemoveItem(shell_cluster, true) ~= shell_cluster then
        return false
    end

    if shell_cluster:IsValid() then
        shell_cluster:Remove()
    end
    if salvage:IsValid() then
        salvage:Remove()
    end

    inst._salvaged_shell_cluster_count =
        (inst._salvaged_shell_cluster_count or 0) + 1
    return true
end

-- 真实贝壳堆不足六处时，沿用原来的随机海面取点逻辑补足。
local function FillIslandWaterPoints(inst, points)
    local center = inst._island_center or inst:GetPosition()
    local sector = TWOPI / tuning.COUNT
    local start_angle = math.random() * TWOPI

    for index = 1, tuning.COUNT do
        if #points >= tuning.COUNT then
            break
        end

        local sector_angle = start_angle + (index - 1) * sector
        for _ = 1, 30 do
            local angle = sector_angle + (math.random() - 0.5) * sector * 0.8
            local radius = tuning.WATER_MIN_RADIUS
                + math.random() * (tuning.WATER_MAX_RADIUS - tuning.WATER_MIN_RADIUS)
            local x = center.x + radius * math.cos(angle)
            local z = center.z - radius * math.sin(angle)
            if TryAddWaterPoint(points, x, z) then
                break
            end
        end
    end

    for _ = 1, 300 do
        if #points >= tuning.COUNT then
            break
        end

        local angle = math.random() * TWOPI
        local radius = tuning.WATER_MIN_RADIUS
            + math.random() * (tuning.WATER_MAX_RADIUS - tuning.WATER_MIN_RADIUS)
        TryAddWaterPoint(
            points,
            center.x + radius * math.cos(angle),
            center.z - radius * math.sin(angle)
        )
    end

    local radius = tuning.WATER_MIN_RADIUS
    while #points < tuning.COUNT and radius <= tuning.WATER_FALLBACK_RADIUS do
        for step = 0, 71 do
            local angle = start_angle + step * TWOPI / 72
            TryAddWaterPoint(
                points,
                center.x + radius * math.cos(angle),
                center.z - radius * math.sin(angle)
            )
            if #points >= tuning.COUNT then
                break
            end
        end
        radius = radius + 1
    end

    return points
end

local function Spawn(inst)
    if inst._shell_phase_released or inst._encounter_resolved or inst._surrendering then
        return
    end

    inst._shell_phase_released = true
    inst._orbit_shells = inst._orbit_shells or {}

    local points = {}
    for _, source in ipairs(FindSunkenShellClusters(inst)) do
        if ConsumeSunkenShellCluster(inst, source) then
            table.insert(points, source.point)
        end
    end
    FillIslandWaterPoints(inst, points)

    local orbit_start_angle = math.random() * TWOPI
    local waterspout_hit_targets = {}
    for index, point in ipairs(points) do
        local waterspout = SpawnPrefab("crab_king_waterspout")
        if waterspout ~= nil then
            waterspout.Transform:SetPosition(point:Get())
        end
        DoWaterspoutDamage(inst, point, waterspout, waterspout_hit_targets)

        local shell = SpawnPrefab("hermitcrab_boss_shell")
        if shell ~= nil then
            shell.Transform:SetPosition(point:Get())
            shell:SetBoss(inst, index, #points, orbit_start_angle)
            table.insert(inst._orbit_shells, shell)
        end
    end
end

local function Begin(inst)
    if inst._shell_phase_triggered or inst._encounter_resolved or inst._surrendering then
        return
    end

    inst._shell_phase_triggered = true
    inst.components.combat:CancelAttack()
    inst:PushEvent("hermitboss_shell_phase")
end

local function OnHealthDelta(inst, data)
    if not inst._shell_phase_triggered
        and not inst._surrendering
        and inst.components.health.currenthealth > inst.components.health.minhealth
        and data ~= nil
        and data.oldpercent > tuning.PHASE_HEALTH
        and data.newpercent <= tuning.PHASE_HEALTH then
        Begin(inst)
    end
end

local function RemoveOrbitShells(inst)
    if inst._orbit_shells == nil then
        return
    end

    for _, shell in ipairs(inst._orbit_shells) do
        if shell:IsValid() then
            shell:Remove()
        end
    end
    inst._orbit_shells = nil
end

local function OnEncounterFinished(inst, data)
    RemoveOrbitShells(inst)
    inst._shell_hit_cooldowns = nil

    if (inst._salvaged_shell_cluster_count or 0) <= 0 then
        return
    end
    inst._salvaged_shell_cluster_count = nil

    local hermit = data ~= nil and data.hermit or nil
    if hermit == nil or not hermit:IsValid() then
        return
    end

    -- 原版通过该事件重新扫描岛屿水域，没有单独维护已打捞数量。
    TheWorld:DoTaskInTime(0, function()
        if hermit:IsValid() then
            TheWorld:PushEvent("CHEVO_heavyobject_winched", {
                target = hermit,
                doer = nil,
            })
        end
    end)
end

function ShellRing.Attach(inst, encounter_finished_event)
    inst.SpawnShellRing = Spawn
    inst.TryShellContactHit = TryContactHit

    inst:ListenForEvent("healthdelta", OnHealthDelta)
    inst:ListenForEvent(encounter_finished_event, OnEncounterFinished)
end

return ShellRing
