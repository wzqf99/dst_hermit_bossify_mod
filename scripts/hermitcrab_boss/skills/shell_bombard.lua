-- ============================================================================
-- 贝壳聚拢轰炸技能：75% 贝壳环首次召唤后，每 REPEAT_INTERVAL 秒释放一次。
--
-- 状态流转 ORBIT → GATHER → SPIN → THROW → RETURN → ORBIT：
--   1. ORBIT   贝壳按原轨道环绕 Boss（本模块不接管）。
--   2. GATHER  施法前摇后，所有存活贝壳脱离轨道，飞向 Boss 头顶聚拢。
--   3. SPIN    贝壳在头顶高速旋转蓄力。
--   4. THROW   蓄力完成后，贝壳砸向周围玩家的目标落点（先落点预警）。
--   5. RETURN  未被摧毁的贝壳飞回 Boss，按剩余数量重新分配均匀轨道。
--   6. ORBIT   恢复环绕（贝壳实体的 UpdatePosition 重新接管）。
--
-- 复用现有 hermitcrab_boss_shell 实体（外观、破碎、接触伤害），本模块只负责
-- 在技能期间逐帧控制贝壳位置；技能结束交还轨道控制（RecalcOrbitAngle）。
-- 被摧毁的贝壳不会重新生成：技能只操作 inst._orbit_shells 中仍 IsValid 的实体，
-- 剩余贝壳数量天然减少，返回时按存活数量重新均分角度。
-- ============================================================================

local events = require("hermitcrab_boss/events")
local tuning = require("hermitcrab_boss/tuning").SHELL_BOMBARD

local ShellBombard =
{
    -- 落点预警水柱（crab_king_waterspout）与落地特效（rock_break_fx）由本技能生成；
    -- 贝壳实体复用 shell_ring 生成的 hermitcrab_boss_shell，不在此重复声明。
    PREFABS =
    {
        "crab_king_waterspout",
        "rock_break_fx",
    },
}

-- 技能状态机
local STATE =
{
    IDLE = "IDLE",         -- 未激活（贝壳正常环绕）
    GATHER = "GATHER",     -- 聚拢：脱离轨道飞向头顶
    SPIN = "SPIN",         -- 旋转蓄力
    THROW = "THROW",       -- 投掷：飞向落点
    RETURN = "RETURN",     -- 返回：飞回 Boss 并重算轨道
}

local PLAYER_MUST_TAGS = { "player" }
local PLAYER_CANT_TAGS = { "playerghost", "INLIMBO" }

--------------------------------------------------------------------------
-- 前向声明：以下函数在文件中定义在调用方之后，需先声明 local 名字，
-- 再以 `Name = function(...)` 形式赋值，避免 Lua 严格模式下因
-- 调用时还未声明而报 "variable 'X' is not declared"。
-- 调用图：UpdateGather→BeginSpin, UpdateSpin→BeginThrow,
--         UpdateThrow→ImpactAll, ImpactAll→BeginReturn,
--         BeginGather→AbortSkill, Step→各 Update, StartBombard→BeginGather。
--------------------------------------------------------------------------
local AbortSkill
local BeginGather
local BeginSpin
local BeginThrow
local ImpactAll
local BeginReturn
local UpdateGather
local UpdateSpin
local UpdateThrow
local UpdateReturn
local Step

--------------------------------------------------------------------------
-- 状态门控：技能期间遇到战斗结束 / 最终阶段 / 投降时立即中断并交还轨道。
--------------------------------------------------------------------------
local function IsInterrupted(inst)
    return inst._encounter_resolved
        or inst._surrendering
        or inst._final_phase_triggered
end

-- 两阶段间的线性插值（带 ease-in-out，让移动更自然）。
local function EaseInOut(t)
    return t * t * (3 - 2 * t)
end

local function ShellPos(shell)
    return shell.Transform:GetWorldPosition()
end

local function SetShellPos(shell, x, y, z)
    shell.Transform:SetPosition(x, y, z)
end

--------------------------------------------------------------------------
-- 存活贝壳收集：只返回仍有效且未被摧毁的贝壳。
--------------------------------------------------------------------------
local function CollectLivingShells(inst)
    local shells = {}
    for _, shell in ipairs(inst._orbit_shells or {}) do
        if shell ~= nil and shell:IsValid() then
            table.insert(shells, shell)
        end
    end
    return shells
end

-- 收集 Boss 周围可被轰炸的存活玩家（用于分配落点）。
local function CollectPlayers(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local players = {}
    for _, player in ipairs(TheSim:FindEntities(
        x, y, z, tuning.TARGET_RANGE, PLAYER_MUST_TAGS, PLAYER_CANT_TAGS
    )) do
        if player.components.health ~= nil
            and not player.components.health:IsDead() then
            table.insert(players, player)
        end
    end
    return players
end

--------------------------------------------------------------------------
-- 轨道重算：按当前存活贝壳数量均匀分配角度，并交还轨道控制。
--------------------------------------------------------------------------
local function ReassignOrbit(inst, shells)
    local living = {}
    for _, shell in ipairs(shells) do
        if shell ~= nil and shell:IsValid() then
            table.insert(living, shell)
        end
    end

    local count = #living
    if count <= 0 then
        return
    end

    local start_angle = math.random() * TWOPI
    for index, shell in ipairs(living) do
        shell._orbit_index = index
        shell:RecalcOrbitAngle(count, start_angle)
    end
end

--------------------------------------------------------------------------
-- 中断清理：交还所有存活贝壳的轨道控制，让贝壳回到正常环绕。
--------------------------------------------------------------------------
AbortSkill = function(inst)
    if inst._bombard_state == STATE.IDLE then
        return
    end

    inst._bombard_state = STATE.IDLE
    if inst._bombard_task ~= nil then
        inst._bombard_task:Cancel()
        inst._bombard_task = nil
    end

    local shells = CollectLivingShells(inst)
    ReassignOrbit(inst, shells)
end

--------------------------------------------------------------------------
-- GATHER：所有贝壳从当前位置飞向头顶聚合点。
--------------------------------------------------------------------------
BeginGather = function(inst, shells)
    if #shells <= 0 or IsInterrupted(inst) then
        AbortSkill(inst)
        return
    end

    inst._bombard_state = STATE.GATHER
    inst._bombard_start_time = GetTime()

    local boss_x, boss_y, boss_z = inst.Transform:GetWorldPosition()
    inst._bombard_shell_entries = {}

    for index, shell in ipairs(shells) do
        if shell:IsValid() then
            shell:SetControlMode("BOMBARD")
            local sx, sy, sz = ShellPos(shell)
            -- 聚合点：头顶上方，围绕中心按 index 均分角度（保持分散）。
            local angle = (index - 1) * TWOPI / #shells
            inst._bombard_shell_entries[shell] =
            {
                start = { x = sx, y = sy, z = sz },
                angle = angle,
            }
        end
    end
end

UpdateGather = function(inst)
    local elapsed = GetTime() - inst._bombard_start_time
    local duration = tuning.GATHER_DURATION

    local boss_x, boss_y, boss_z = inst.Transform:GetWorldPosition()

    if elapsed >= duration then
        BeginSpin(inst)
        return
    end

    local t = EaseInOut(elapsed / duration)
    for shell, entry in pairs(inst._bombard_shell_entries or {}) do
        if shell:IsValid() then
            local sx, sy, sz = entry.start.x, entry.start.y, entry.start.z
            local tx = boss_x + tuning.GATHER_RADIUS * math.cos(entry.angle)
            local ty = boss_y + tuning.GATHER_HEIGHT
            local tz = boss_z - tuning.GATHER_RADIUS * math.sin(entry.angle)
            SetShellPos(
                shell,
                sx + (tx - sx) * t,
                sy + (ty - sy) * t,
                sz + (tz - sz) * t
            )
        end
    end
end

--------------------------------------------------------------------------
-- SPIN：贝壳在头顶高速旋转蓄力。
--------------------------------------------------------------------------
BeginSpin = function(inst)
    inst._bombard_state = STATE.SPIN
    inst._bombard_spin_start = GetTime()
end

UpdateSpin = function(inst)
    local elapsed = GetTime() - inst._bombard_spin_start
    local duration = tuning.SPIN_DURATION

    local boss_x, boss_y, boss_z = inst.Transform:GetWorldPosition()
    local spin_angle = elapsed * tuning.SPIN_ANGULAR_SPEED

    for shell, entry in pairs(inst._bombard_shell_entries or {}) do
        if shell:IsValid() then
            local angle = entry.angle + spin_angle
            SetShellPos(
                shell,
                boss_x + tuning.GATHER_RADIUS * math.cos(angle),
                boss_y + tuning.GATHER_HEIGHT,
                boss_z - tuning.GATHER_RADIUS * math.sin(angle)
            )
        end
    end

    if elapsed >= duration then
        BeginThrow(inst)
    end
end

--------------------------------------------------------------------------
-- THROW：贝壳砸向玩家落点。先显示落点预警，预警结束后贝壳飞行并落地伤害。
--------------------------------------------------------------------------
BeginThrow = function(inst)
    inst._bombard_state = STATE.THROW
    inst._bombard_throw_start = GetTime()

    -- 收集仍存活的贝壳。
    local shells = {}
    for shell in pairs(inst._bombard_shell_entries or {}) do
        if shell:IsValid() then
            table.insert(shells, shell)
        end
    end

    if #shells <= 0 then
        AbortSkill(inst)
        return
    end

    local players = CollectPlayers(inst)
    inst._bombard_throw_entries = {}
    inst._bombard_flight_starts = nil

    for index, shell in ipairs(shells) do
        local aim_x, aim_z
        if #players > 0 then
            -- 轮询分配玩家，保证多玩家时落点分散。
            local player = players[((index - 1) % #players) + 1]
            local px, _, pz = player.Transform:GetWorldPosition()
            local scatter_angle = math.random() * TWOPI
            local scatter_r = math.random() * tuning.IMPACT_SCATTER
            aim_x = px + scatter_r * math.cos(scatter_angle)
            aim_z = pz - scatter_r * math.sin(scatter_angle)
        else
            -- 无玩家时，随机落在 Boss 周围，避免报错。
            local bx, _, bz = inst.Transform:GetWorldPosition()
            local scatter_angle = math.random() * TWOPI
            aim_x = bx + tuning.IMPACT_SCATTER * math.cos(scatter_angle)
            aim_z = bz - tuning.IMPACT_SCATTER * math.sin(scatter_angle)
        end

        inst._bombard_throw_entries[shell] =
        {
            aim_x = aim_x,
            aim_z = aim_z,
        }

        -- 落点预警：水柱标记，给玩家走位空间。
        local fx = SpawnPrefab("crab_king_waterspout")
        if fx ~= nil then
            fx.Transform:SetPosition(aim_x, 0, aim_z)
        end
    end
end

UpdateThrow = function(inst)
    local elapsed = GetTime() - inst._bombard_throw_start
    local warning = tuning.IMPACT_WARNING
    local flight = tuning.THROW_DURATION

    -- 预警阶段：贝壳停在头顶继续旋转。
    if elapsed < warning then
        local boss_x, boss_y, boss_z = inst.Transform:GetWorldPosition()
        local spin_angle = (elapsed + tuning.SPIN_DURATION)
            * tuning.SPIN_ANGULAR_SPEED
        for shell, entry in pairs(inst._bombard_shell_entries or {}) do
            if shell:IsValid() then
                local angle = entry.angle + spin_angle
                SetShellPos(
                    shell,
                    boss_x + tuning.GATHER_RADIUS * math.cos(angle),
                    boss_y + tuning.GATHER_HEIGHT,
                    boss_z - tuning.GATHER_RADIUS * math.sin(angle)
                )
            end
        end
        return
    end

    local flight_elapsed = elapsed - warning
    if flight_elapsed >= flight then
        ImpactAll(inst)
        return
    end

    -- 飞行首帧记录起点（预警阶段刚结束时的头顶位置），
    -- 之后以固定起点向落点插值；若每帧用当前位置作起点，会变成
    -- “渐近逼近”，表现为前段几乎不动、末帧瞬移到落点。
    if inst._bombard_flight_starts == nil then
        inst._bombard_flight_starts = {}
        for shell in pairs(inst._bombard_throw_entries or {}) do
            if shell:IsValid() then
                local sx, sy, sz = ShellPos(shell)
                inst._bombard_flight_starts[shell] = { x = sx, y = sy, z = sz }
            end
        end
    end

    local t = EaseInOut(flight_elapsed / flight)
    local ty = 0.5 -- 落地高度

    for shell, entry in pairs(inst._bombard_throw_entries or {}) do
        if shell:IsValid() then
            local start = inst._bombard_flight_starts[shell]
            if start ~= nil then
                SetShellPos(
                    shell,
                    start.x + (entry.aim_x - start.x) * t,
                    start.y + (ty - start.y) * t,
                    start.z + (entry.aim_z - start.z) * t
                )
            end
        end
    end
end

--------------------------------------------------------------------------
-- 落地：对落点半径内玩家造成伤害，随后进入 RETURN。
--------------------------------------------------------------------------
ImpactAll = function(inst)
    for shell, entry in pairs(inst._bombard_throw_entries or {}) do
        if shell:IsValid() then
            local x, _, z = ShellPos(shell)
            SetShellPos(shell, entry.aim_x, 0.5, entry.aim_z)

            -- 落地特效
            local fx = SpawnPrefab("rock_break_fx")
            if fx ~= nil then
                fx.Transform:SetPosition(entry.aim_x, 0, entry.aim_z)
            end

            -- 范围伤害（由 Boss 造成，保证仇恨归属）。
            for _, target in ipairs(TheSim:FindEntities(
                entry.aim_x, 0, entry.aim_z,
                tuning.IMPACT_DAMAGE_RADIUS + 1,
                PLAYER_MUST_TAGS, PLAYER_CANT_TAGS
            )) do
                if target.components.combat ~= nil
                    and target.components.health ~= nil
                    and not target.components.health:IsDead() then
                    local tx, _, tz = target.Transform:GetWorldPosition()
                    local dx = tx - entry.aim_x
                    local dz = tz - entry.aim_z
                    local radius = tuning.IMPACT_DAMAGE_RADIUS
                        + target:GetPhysicsRadius(0)
                    if dx * dx + dz * dz <= radius * radius then
                        target.components.combat:GetAttacked(
                            inst,
                            tuning.IMPACT_DAMAGE,
                            shell
                        )
                    end
                end
            end
        end
    end

    BeginReturn(inst)
end

--------------------------------------------------------------------------
-- RETURN：存活贝壳飞回 Boss，按剩余数量重算均匀轨道，恢复环绕。
--------------------------------------------------------------------------
BeginReturn = function(inst)
    inst._bombard_state = STATE.RETURN
    inst._bombard_return_start = GetTime()

    -- 记录返回起点（当前落点位置）与存活贝壳。
    local shells = {}
    for shell in pairs(inst._bombard_throw_entries or {}) do
        if shell:IsValid() then
            shells[shell] = true
        end
    end
    inst._bombard_return_shells = shells
end

UpdateReturn = function(inst)
    local elapsed = GetTime() - inst._bombard_return_start
    local duration = tuning.RETURN_DURATION

    local shells = {}
    for shell in pairs(inst._bombard_return_shells or {}) do
        if shell:IsValid() then
            table.insert(shells, shell)
        end
    end
    local count = #shells

    local boss_x, boss_y, boss_z = inst.Transform:GetWorldPosition()

    if elapsed >= duration or count <= 0 then
        -- 结束：交还轨道控制，重新均分角度，并取消逐帧循环任务，
        -- 否则每轮轰炸都会泄漏一个永不停歇的周期任务。
        ReassignOrbit(inst, shells)
        inst._bombard_state = STATE.IDLE
        if inst._bombard_task ~= nil then
            inst._bombard_task:Cancel()
            inst._bombard_task = nil
        end
        return
    end

    local t = EaseInOut(elapsed / duration)
    for index, shell in ipairs(shells) do
        -- 返回起点：BeginReturn 记录的落点位置，固定起点插值，
        -- 避免每帧用当前位置作起点导致的渐近/瞬移。
        local start = inst._bombard_return_starts ~= nil
            and inst._bombard_return_starts[shell]
            or nil
        local sx, sy, sz
        if start ~= nil then
            sx, sy, sz = start.x, start.y, start.z
        else
            sx, sy, sz = ShellPos(shell)
        end
        -- 返回目标：环绕轨道上的初始角度位置。
        local angle = (index - 1) * TWOPI / count
        local tx = boss_x + tuning.GATHER_RADIUS * math.cos(angle)
        local ty = boss_y + 0.8
        local tz = boss_z - tuning.GATHER_RADIUS * math.sin(angle)
        SetShellPos(
            shell,
            sx + (tx - sx) * t,
            sy + (ty - sy) * t,
            sz + (tz - sz) * t
        )
    end
end

--------------------------------------------------------------------------
-- 主循环：每帧推进状态机。
--------------------------------------------------------------------------
Step = function(inst)
    if IsInterrupted(inst) then
        AbortSkill(inst)
        return
    end

    local state = inst._bombard_state
    if state == STATE.GATHER then
        UpdateGather(inst)
    elseif state == STATE.SPIN then
        UpdateSpin(inst)
    elseif state == STATE.THROW then
        UpdateThrow(inst)
    elseif state == STATE.RETURN then
        UpdateReturn(inst)
    end
end

--------------------------------------------------------------------------
-- 技能启动：施法前摇后进入 GATHER。
--------------------------------------------------------------------------
local function StartBombard(inst)
    if IsInterrupted(inst) then
        return
    end

    local shells = CollectLivingShells(inst)
    if #shells <= 0 then
        -- 没有存活贝壳时，跳过本轮（下一轮循环时若贝壳仍为空则继续空转）。
        inst._bombard_state = STATE.IDLE
        inst._bombard_task = nil
        return
    end

    -- 施法前摇：Boss 播放施法动画，贝壳保持原轨道（本模块暂不接管）。
    inst._bombard_state = STATE.IDLE
    inst._bombard_task = inst:DoTaskInTime(tuning.CAST_DURATION, function()
        inst._bombard_task = nil
        if not IsInterrupted(inst) then
            local live = CollectLivingShells(inst)
            if #live > 0 then
                BeginGather(inst, live)
                -- 启动逐帧循环。
                inst._bombard_task = inst:DoPeriodicTask(FRAMES, Step, 0)
            end
        end
    end)
end

-- 由 SG 施法状态在动画帧调用（进入施法动画）。
local function CastBombard(inst)
    if inst._bombard_running
        or inst._final_phase_triggered
        or inst._encounter_resolved
        or inst._surrendering then
        return
    end

    inst._bombard_running = true
    StartBombard(inst)
end

--------------------------------------------------------------------------
-- 循环调度：贝壳环首次召唤后每 REPEAT_INTERVAL 秒触发一次。
-- 监听 SHELL_PHASE（贝壳环生成完毕），随后启动周期任务，每次推事件走施法动画。
--------------------------------------------------------------------------
local function OnShellPhase(inst)
    if inst._bombard_loop_task ~= nil then
        return
    end

    inst._bombard_loop_task = inst:DoPeriodicTask(
        tuning.REPEAT_INTERVAL,
        function()
            if IsInterrupted(inst) then
                StopLoop(inst)
                return
            end
            -- 允许再次施法，走 SG 施法状态。
            inst._bombard_running = nil
            inst.components.combat:CancelAttack()
            inst:PushEvent(events.SHELL_BOMBARD)
        end,
        tuning.REPEAT_INTERVAL
    )
end

local function StopLoop(inst)
    if inst._bombard_loop_task ~= nil then
        inst._bombard_loop_task:Cancel()
        inst._bombard_loop_task = nil
    end
end

local function OnEncounterFinished(inst)
    StopLoop(inst)
    if inst._bombard_task ~= nil then
        inst._bombard_task:Cancel()
        inst._bombard_task = nil
    end
    inst._bombard_state = STATE.IDLE
    inst._bombard_running = nil
end

function ShellBombard.Attach(inst)
    inst.CastShellBombard = CastBombard
    inst.TriggerShellBombard = CastBombard

    -- 贝壳环生成后启动循环调度。
    inst:ListenForEvent(events.SHELL_PHASE, function()
        OnShellPhase(inst)
    end)

    inst:ListenForEvent(events.ENCOUNTER_FINISHED, OnEncounterFinished)
    inst:ListenForEvent(events.FINAL_PHASE_STARTED, OnEncounterFinished)
end

return ShellBombard
