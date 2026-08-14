-- ============================================================================
-- 阶段调度器：统一负责"血量阈值 → 阶段技能"的触发判定。
-- 各技能模块不再各自监听 healthdelta，而是通过 RegisterPhase 注册：
--   PhaseScheduler.RegisterPhase({
--       threshold = 0.5,            -- 掉血跨过该百分比时触发
--       event = events.KELP_SNARE,  -- 事件名（用于互斥去重）
--       trigger = function(inst) inst:TriggerKelpSnare() end,
--   })
-- 触发函数内部负责置位 inst._phase_triggered[event]，实现自包含互斥，
-- 脱离调度器（如调试指令）调用时行为一致。
--
-- 关键保证：一次掉血只触发"最深"（阈值最低）的未触发阶段。
-- 高额伤害可能一次跨过多个阈值，若全部触发会导致同帧多点进入状态机、
-- SG 状态互相覆盖；而最终阶段会清理其余技能实体，因此只进最深阶段即可。
-- 同阈值的多个阶段视为同一档（例如 50% 拆出的"牢笼 / 螺旋"两个海带技能），
-- 一并触发；它们共用同一个施法状态，同帧多次进入同一状态不会互相覆盖。
-- ============================================================================
local PhaseScheduler = {}

PhaseScheduler.PHASES = {}

function PhaseScheduler.RegisterPhase(phase)
    if phase ~= nil
        and type(phase.threshold) == "number"
        and type(phase.event) == "string"
        and type(phase.trigger) == "function" then
        table.insert(PhaseScheduler.PHASES, phase)
    end
end

-- 本次掉血跨越的未触发阶段中，阈值最低（最深）的一档。
-- 返回该档阈值；同阈值的多个阶段视为同一档（例如 50% 的牢笼 / 螺旋）。
local function FindDeepestThreshold(inst, data)
    local deepest = nil
    for _, phase in ipairs(PhaseScheduler.PHASES) do
        if not inst._phase_triggered[phase.event]
            and data.oldpercent > phase.threshold
            and data.newpercent <= phase.threshold then
            if deepest == nil or phase.threshold < deepest then
                deepest = phase.threshold
            end
        end
    end
    return deepest
end

local function OnHealthDelta(inst, data)
    if inst._encounter_resolved or inst._surrendering then
        return
    end
    if data == nil
        or data.oldpercent == nil
        or data.newpercent == nil
        or data.newpercent >= data.oldpercent then
        return
    end

    local threshold = FindDeepestThreshold(inst, data)
    if threshold ~= nil then
        -- 只触发最深一档；同档（同阈值）的多个阶段一并触发。
        for _, phase in ipairs(PhaseScheduler.PHASES) do
            if not inst._phase_triggered[phase.event]
                and phase.threshold == threshold
                and data.oldpercent > phase.threshold
                and data.newpercent <= phase.threshold then
                phase.trigger(inst)
            end
        end
    end
end

function PhaseScheduler.Attach(inst)
    inst._phase_triggered = inst._phase_triggered or {}
    inst:ListenForEvent("healthdelta", OnHealthDelta)
end

-- 查询某阶段是否已触发。调度器未挂载时按"未触发"处理（nil 安全）。
function PhaseScheduler.IsTriggered(inst, event)
    return inst._phase_triggered ~= nil and inst._phase_triggered[event]
end

-- 标记某阶段已触发（幂等，nil 安全）。
function PhaseScheduler.MarkTriggered(inst, event)
    if inst._phase_triggered ~= nil then
        inst._phase_triggered[event] = true
    end
end

-- 供调试（c_sc 等）重置某阶段标志，允许再次触发。
function PhaseScheduler.ResetPhase(inst, event)
    if inst._phase_triggered ~= nil then
        inst._phase_triggered[event] = nil
    end
end

return PhaseScheduler
