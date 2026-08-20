-- ============================================================================
-- 保持距离 + 远程攻击：Boss 一阶段投瓶走位。
--
--   - 玩家距离 < min_dist：后退（远离玩家，保持投瓶距离）
--   - 玩家距离 > 攻击距离：靠近（跑向玩家）
--   - 中间区间：停下、面向玩家、TryAttack（投瓶由 combat 攻击周期驱动）
--
-- 仅在 inst._bottle_mode 为 true 时生效，否则 FAILED，让 ChaseAndAttack
-- 接管 75% 之后的近战行为。
-- ============================================================================

KeepDistanceAndAttack = Class(BehaviourNode, function(self, inst, min_dist, retreat_run, max_chase_time, give_up_dist)
    BehaviourNode._ctor(self, "KeepDistanceAndAttack")
    self.inst = inst
    self.min_dist = min_dist
    self.retreat_run = retreat_run
    self.max_chase_time = max_chase_time
    self.give_up_dist = give_up_dist
    self.startruntime = nil
end)

function KeepDistanceAndAttack:__tostring()
    return string.format("KeepDistanceAndAttack target %s",
        tostring(self.inst.components.combat.target))
end

function KeepDistanceAndAttack:Visit()
    local combat = self.inst.components.combat

    if self.status == READY then
        combat:ValidateTarget()

        if not self.inst._bottle_mode then
            self.status = FAILED
            return
        end

        if combat.target ~= nil then
            combat:BattleCry()
            self.startruntime = GetTime()
            self.status = RUNNING
        else
            self.status = FAILED
        end
    end

    if self.status == RUNNING then
        local target = combat.target

        if not self.inst._bottle_mode then
            -- 已切回近战模式：让后面的 ChaseAndAttack 接手。
            self.status = FAILED
            self.inst.components.locomotor:Stop()
            return
        end

        if target == nil or not target.entity:IsValid() then
            self.status = FAILED
            combat:SetTarget(nil)
            self.inst.components.locomotor:Stop()
        elseif target.components.health ~= nil and target.components.health:IsDead() then
            self.status = SUCCESS
            combat:SetTarget(nil)
            self.inst.components.locomotor:Stop()
        else
            local hp = Point(target.Transform:GetWorldPosition())
            local pt = Point(self.inst.Transform:GetWorldPosition())
            local dsq = distsq(hp, pt)
            local dist = math.sqrt(dsq)

            -- 攻击动画（投瓶）期间不后退，避免打断投瓶动作。
            local is_attacking = self.inst.sg:HasStateTag("attack")

            if not self.inst.sg:HasStateTag("longattack") then
                if dist < self.min_dist and not is_attacking then
                    -- 太近：后退（远离玩家）。
                    local away_angle = self.inst:GetAngleToPoint(hp) + 180
                    if away_angle > 360 then
                        away_angle = away_angle - 360
                    end
                    if self.retreat_run then
                        self.inst.components.locomotor:RunInDirection(away_angle)
                    else
                        self.inst.components.locomotor:WalkInDirection(away_angle)
                    end
                elseif dsq > combat:CalcAttackRangeSq() then
                    -- 太远：跑向玩家。
                    self.inst.components.locomotor:GoToPoint(hp, nil, true)
                else
                    -- 适中：停下、面向玩家。
                    self.inst.components.locomotor:Stop()
                    if self.inst.sg:HasStateTag("canrotate") then
                        self.inst:FacePoint(hp)
                    end
                end
            end

            if combat:TryAttack() then
                -- 投瓶已触发（由 combat 攻击周期驱动）。
            elseif self.startruntime == nil then
                self.startruntime = GetTime()
                combat:BattleCry()
            end

            if (self.give_up_dist ~= nil and dist >= self.give_up_dist)
                or (self.max_chase_time ~= nil
                    and self.startruntime ~= nil
                    and GetTime() - self.startruntime > self.max_chase_time) then
                self.status = FAILED
                combat:GiveUp()
                self.inst.components.locomotor:Stop()
                return
            end

            self:Sleep(0.125)
        end
    end
end
