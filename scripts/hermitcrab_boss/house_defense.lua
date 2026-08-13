local tuning = require("hermitcrab_boss/tuning").FINAL_PHASE

local HouseDefense =
{
    ACTIVE_STATE = "HOUSE_DEFENSE",
    PREFABS =
    {
        "alterguardian_laser",
        "wagboss_missile",
    },
}

local HOUSE_PREFABS =
{
    "hermithouse_construction1",
    "hermithouse_construction2",
    "hermithouse_construction3",
    "hermithouse",
    "hermithouse2",
}

local function IsActive(inst)
    return inst._final_state == HouseDefense.ACTIVE_STATE
        and not inst._encounter_resolved
end

local function CancelTask(owner, name)
    local task = owner[name]
    if task ~= nil then
        task:Cancel()
        owner[name] = nil
    end
end

local function IsLivingIslandPlayer(inst, player)
    if player == nil
        or not player:IsValid()
        or player:HasTag("playerghost")
        or player:IsInLimbo()
        or (player.components.health ~= nil
            and player.components.health:IsDead()) then
        return false
    end

    local center = inst._island_center or inst:GetPosition()
    return player:GetDistanceSqToPoint(center.x, 0, center.z)
        <= tuning.ISLAND_RADIUS * tuning.ISLAND_RADIUS
end

local function CollectIslandPlayers(inst)
    local players = {}
    for _, player in ipairs(AllPlayers) do
        if IsLivingIslandPlayer(inst, player) then
            table.insert(players, player)
        end
    end
    return players
end

local function FindHouse(inst)
    local manager = TheWorld.components.hermitcrab_relocation_manager
    local house = manager ~= nil and manager:GetPearlsHouse() or nil
    if house ~= nil and house:IsValid() then
        return house
    end

    local center = inst._island_center or inst:GetPosition()
    local nearest = nil
    local nearest_distance_sq = math.huge
    for _, candidate in ipairs(TheSim:FindEntities(
        center.x,
        0,
        center.z,
        tuning.ISLAND_RADIUS,
        { "hermithouse" }
    )) do
        if candidate:IsValid() then
            local distance_sq = candidate:GetDistanceSqToPoint(
                center.x,
                0,
                center.z
            )
            if distance_sq < nearest_distance_sq then
                nearest = candidate
                nearest_distance_sq = distance_sq
            end
        end
    end
    return nearest
end

local function RemoveMissile(inst, missile, onremove)
    if onremove ~= nil and inst.event_listening ~= nil then
        inst:RemoveEventCallback("onremove", onremove, missile)
    end
    if inst._final_missiles ~= nil then
        inst._final_missiles[missile] = nil
    end
    if inst._final_missile_remove_fns ~= nil then
        inst._final_missile_remove_fns[missile] = nil
    end
end

local function RemoveAllMissiles(inst)
    local missiles = inst._final_missiles or {}
    local remove_fns = inst._final_missile_remove_fns or {}
    inst._final_missiles = nil
    inst._final_missile_remove_fns = nil
    inst._final_target_cursor = nil

    for missile, onremove in pairs(remove_fns) do
        if missile:IsValid() then
            inst:RemoveEventCallback("onremove", onremove, missile)
        end
    end
    for missile in pairs(missiles) do
        if missile:IsValid() then
            missile:CancelTargetLock()
            missile:Remove()
        end
    end
end

local function TryRetargetMissiles(inst)
    if not IsActive(inst) then
        return
    end

    local targets = CollectIslandPlayers(inst)
    local target_index = 1
    local missiles = inst._final_missiles or {}
    for missile in pairs(missiles) do
        if not missile:IsValid() then
            RemoveMissile(inst, missile)
        elseif not IsLivingIslandPlayer(inst, missile.target) then
            if #targets > 0 then
                missile:Retarget(targets[target_index])
                target_index = target_index % #targets + 1
            else
                missile:CancelTargetLock()
                missile:Remove()
            end
        end
    end
end

local LaunchMissiles

local function ScheduleMissileVolley(inst)
    CancelTask(inst, "_final_missile_task")
    if IsActive(inst) then
        local delay = GetRandomMinMax(
            tuning.MISSILE_INTERVAL_MIN,
            tuning.MISSILE_INTERVAL_MAX
        )
        inst._final_missile_task = inst:DoTaskInTime(delay, function()
            inst._final_missile_task = nil
            LaunchMissiles(inst)
        end)
    end
end

LaunchMissiles = function(inst)
    local house = inst._final_house
    if not IsActive(inst) or house == nil or not house:IsValid() then
        return
    end

    local active_count = 0
    for missile in pairs(inst._final_missiles or {}) do
        if missile:IsValid() then
            active_count = active_count + 1
        else
            RemoveMissile(inst, missile)
        end
    end

    local targets = CollectIslandPlayers(inst)
    local available = tuning.MISSILE_MAX_COUNT - active_count
    if #targets > 0 and available > 0 then
        inst._final_missiles = inst._final_missiles or {}
        inst._final_missile_remove_fns = inst._final_missile_remove_fns or {}

        local count = math.min(available, #targets)
        local target_cursor = inst._final_target_cursor or 1
        local direction = math.random() * 360
        local direction_step = 360 / count
        local group_targets = {}

        for index = 1, count do
            local missile = SpawnPrefab("wagboss_missile")
            if missile ~= nil then
                local target = targets[((target_cursor + index - 2) % #targets) + 1]
                missile:Launch(index, house, target, direction, group_targets)
                inst._final_missiles[missile] = true

                local onremove
                onremove = function()
                    RemoveMissile(inst, missile, onremove)
                end
                inst._final_missile_remove_fns[missile] = onremove
                inst:ListenForEvent("onremove", onremove, missile)

                missile:DoTaskInTime(tuning.MISSILE_SHOW_DELAY, function()
                    if missile:IsValid() then
                        missile:ShowMissile()
                    end
                end)
                direction = direction + direction_step
            end
        end
        inst._final_target_cursor = (target_cursor + count - 1) % #targets + 1
    end

    ScheduleMissileVolley(inst)
end

local SpawnLaserSweep

local function ScheduleLaserSweep(inst)
    CancelTask(inst, "_final_laser_task")
    if IsActive(inst) then
        local delay = GetRandomMinMax(
            tuning.LASER_INTERVAL_MIN,
            tuning.LASER_INTERVAL_MAX
        )
        inst._final_laser_task = inst:DoTaskInTime(delay, function()
            inst._final_laser_task = nil
            SpawnLaserSweep(inst)
        end)
    end
end

local function SpawnLaserNode(inst, house, x, z, targets, skip_toss)
    if not IsActive(inst) or not house:IsValid() then
        return
    end

    local laser = SpawnPrefab("alterguardian_laser")
    if laser ~= nil then
        laser.caster = house
        laser:OverrideDamage(tuning.LASER_DAMAGE, 1)
        laser.Transform:SetPosition(x, 0, z)
        laser:Trigger(
            0,
            targets,
            skip_toss,
            false,
            nil,
            nil,
            tuning.LASER_HIT_SCALE
        )
    end
end

SpawnLaserSweep = function(inst)
    local house = inst._final_house
    if not IsActive(inst) or house == nil or not house:IsValid() then
        return
    end

    local center = inst._island_center or house:GetPosition()
    local start_angle = math.random() * TWOPI
    local points_per_beam = math.max(
        1,
        math.floor(tuning.LASER_POINTS / tuning.LASER_BEAM_COUNT)
    )
    local shared_targets = {}
    local shared_skip_toss = {}

    inst._final_laser_delays = inst._final_laser_delays or {}
    for beam = 1, tuning.LASER_BEAM_COUNT do
        local angle = start_angle
            + (beam - 1) * TWOPI / tuning.LASER_BEAM_COUNT
            + (math.random() - 0.5) * 0.3
        for step = 1, points_per_beam do
            local percent = points_per_beam > 1
                and (step - 1) / (points_per_beam - 1)
                or 0
            local radius = tuning.LASER_MIN_RADIUS
                + percent * (tuning.LASER_MAX_RADIUS - tuning.LASER_MIN_RADIUS)
            local x = center.x + radius * math.cos(angle)
            local z = center.z - radius * math.sin(angle)
            local delay = (step - 1) * tuning.LASER_POINT_INTERVAL
                + (beam - 1) * FRAMES
            local task
            task = inst:DoTaskInTime(delay, function()
                inst._final_laser_delays[task] = nil
                SpawnLaserNode(
                    inst,
                    house,
                    x,
                    z,
                    shared_targets,
                    shared_skip_toss
                )
            end)
            inst._final_laser_delays[task] = true
        end
    end

    ScheduleLaserSweep(inst)
end

local function CancelLaserDelays(inst)
    for task in pairs(inst._final_laser_delays or {}) do
        task:Cancel()
    end
    inst._final_laser_delays = nil
end

local function RestoreHouse(inst, release_hermit)
    local house = inst._final_house
    if house == nil then
        return
    end

    if house:IsValid() then
        if inst._on_final_house_removed ~= nil then
            inst:RemoveEventCallback("onremove", inst._on_final_house_removed, house)
            inst._on_final_house_removed = nil
        end

        CancelTask(house, "_hermitboss_hit_fx_task")
        house.AnimState:SetAddColour(0, 0, 0, 0)
        house:RemoveTag("epic")
        house:RemoveTag("hostile")
        house:AddTag("noplayertarget")
        house:AddTag("noattack")
        if house.components.constructionsite ~= nil
            and house._hermitboss_construction_was_enabled then
            house.components.constructionsite:Enable()
        end
        house._hermitboss_construction_was_enabled = nil

        if house.components.health ~= nil then
            house.components.health:SetInvincible(true)
            house.components.health:SetPercent(1)
        end
        if house.components.combat ~= nil then
            house.components.combat:SetTarget(nil)
            house.components.combat.playerdamagepercent = nil
        end

        if house.components.spawner ~= nil then
            house.components.spawner.ReleaseChild =
                house._hermitboss_had_release_child_override
                and house._hermitboss_release_child_raw
                or nil
            if release_hermit
                and house.components.spawner:IsOccupied()
                and house.components.spawner.child == inst._encounter_hermit then
                house.components.spawner:ReleaseChild()
            end
        end
        house._hermitboss_release_child = nil
        house._hermitboss_release_child_raw = nil
        house._hermitboss_had_release_child_override = nil
        house._hermitboss_controller = nil
    end

    inst._final_house = nil
end

function HouseDefense.Cleanup(inst, release_hermit)
    CancelTask(inst, "_final_laser_task")
    CancelTask(inst, "_final_missile_task")
    CancelTask(inst, "_final_missile_watch_task")
    CancelLaserDelays(inst)
    RemoveAllMissiles(inst)
    RestoreHouse(inst, release_hermit)
end

local function OnHouseAttacked(house)
    if house._hermitboss_controller == nil
        or house._hermitboss_hit_fx_task ~= nil then
        return
    end

    house.AnimState:SetAddColour(0.35, 0.35, 0.35, 0)
    house._hermitboss_hit_fx_task = house:DoTaskInTime(0.12, function()
        house._hermitboss_hit_fx_task = nil
        if house:IsValid() then
            house.AnimState:SetAddColour(0, 0, 0, 0)
        end
    end)
end

local function OnHouseDefeated(house)
    local controller = house._hermitboss_controller
    if controller ~= nil
        and controller:IsValid()
        and not controller._encounter_resolved then
        controller:FinishEncounter(true)
    end
end

local function ClampDormantHouseHealth(
    house,
    amount,
    overtime,
    cause,
    ignore_invincible,
    afflicter,
    ignore_absorb
)
    if house._hermitboss_controller == nil then
        return 0
    end
    return amount
end

local function ReleaseHermitFromRemovedHouse(inst, house)
    local hermit = inst._encounter_hermit
    if hermit == nil or not hermit:IsValid() or hermit.parent ~= house then
        return
    end

    house:RemoveChild(hermit)
    if hermit:IsInLimbo() then
        hermit:ReturnToScene()
    end
    hermit.Transform:SetPosition(house.Transform:GetWorldPosition())
end

function HouseDefense.Activate(inst)
    local house = FindHouse(inst)
    local hermit = inst._encounter_hermit
    if house == nil
        or not house:IsValid()
        or house:HasTag("burnt")
        or hermit == nil
        or not hermit:IsValid()
        or house.components.spawner == nil
        or house.components.health == nil
        or house.components.combat == nil then
        inst:FinishEncounter(false)
        return false
    end

    local spawner = house.components.spawner
    if spawner.child ~= nil and spawner.child ~= hermit then
        inst:FinishEncounter(false)
        return false
    end

    if hermit.parent ~= nil then
        hermit.parent:RemoveChild(hermit)
    end
    if hermit:IsInLimbo() then
        hermit:ReturnToScene()
    end
    spawner:TakeOwnership(hermit)
    if not spawner:GoHome(hermit) then
        spawner:ReleaseChild()
        inst:FinishEncounter(false)
        return false
    end

    if house.ejectchildtask ~= nil then
        house.ejectchildtask:Cancel()
        house.ejectchildtask = nil
    end
    house._hermitboss_controller = inst
    house._hermitboss_release_child = spawner.ReleaseChild
    house._hermitboss_release_child_raw = rawget(spawner, "ReleaseChild")
    house._hermitboss_had_release_child_override =
        house._hermitboss_release_child_raw ~= nil
    spawner.ReleaseChild = function(self)
        if house._hermitboss_controller == inst
            and inst:IsValid()
            and IsActive(inst) then
            return
        end
        return house._hermitboss_release_child(self)
    end

    house:RemoveTag("noplayertarget")
    house:RemoveTag("noattack")
    house:AddTag("epic")
    house:AddTag("hostile")
    if house.components.constructionsite ~= nil then
        house._hermitboss_construction_was_enabled =
            house.components.constructionsite:IsEnabled()
        house.components.constructionsite:Disable()
    end

    local remaining_health = math.max(
        tuning.HOUSE_MIN_HEALTH,
        inst.components.health.currenthealth
    )
    house.components.health:SetMaxHealth(remaining_health)
    house.components.health:SetMinHealth(1)
    house.components.health:SetPercent(1)
    house.components.health:SetInvincible(false)
    house.components.combat:SetDefaultDamage(tuning.LASER_DAMAGE)
    house.components.combat.playerdamagepercent = 1

    inst._final_house = house
    inst._final_state = HouseDefense.ACTIVE_STATE

    inst.Transform:SetPosition(house.Transform:GetWorldPosition())
    inst:Hide()
    inst.DynamicShadow:Enable(false)
    inst.Physics:ClearCollisionMask()
    inst:AddTag("NOCLICK")
    inst:AddTag("invisible")
    inst.components.health:SetInvincible(true)
    inst.components.combat:SetTarget(nil)

    SpawnLaserSweep(inst)
    LaunchMissiles(inst)
    inst._final_missile_watch_task = inst:DoPeriodicTask(
        tuning.PLAYER_SCAN_PERIOD,
        TryRetargetMissiles,
        tuning.PLAYER_SCAN_PERIOD
    )

    inst._on_final_house_removed = function()
        inst._on_final_house_removed = nil
        ReleaseHermitFromRemovedHouse(inst, house)
        inst._final_house = nil
        if inst:IsValid() and not inst._encounter_resolved then
            inst:FinishEncounter(true)
        end
    end
    inst:ListenForEvent("onremove", inst._on_final_house_removed, house)
    return true
end

function HouseDefense.ConfigureHouse(inst)
    -- Prefab PostInit 会在实体加入世界前补齐这些休眠组件与网络标签。
    if not TheWorld.ismastersim or inst.components.spawner == nil then
        return
    end

    if inst.components.health == nil then
        inst:AddComponent("health")
    end
    inst.components.health:SetMaxHealth(tuning.HOUSE_MIN_HEALTH)
    inst.components.health:SetMinHealth(1)
    inst.components.health:SetInvincible(true)
    inst.components.health.save_maxhealth = false
    inst.components.health.nofadeout = true
    inst.components.health.deltamodifierfn = ClampDormantHouseHealth

    if inst.components.combat == nil then
        inst:AddComponent("combat")
    end
    inst.components.combat:SetDefaultDamage(tuning.LASER_DAMAGE)
    inst.components.combat:SetRange(0)
    inst.components.combat:SetShouldAggroFn(function(_, target)
        return target:HasTag("player")
    end)
    inst.components.combat:SetOnHit(OnHouseAttacked)

    inst:AddTag("noplayertarget")
    inst:AddTag("noattack")
    inst:ListenForEvent("minhealth", OnHouseDefeated)
end

function HouseDefense.RegisterHousePostInits(add_prefab_post_init)
    for _, prefab in ipairs(HOUSE_PREFABS) do
        add_prefab_post_init(prefab, HouseDefense.ConfigureHouse)
    end
end

return HouseDefense
