-- ============================================================================
-- Boss 行为树（Brain）：巡逻 → 追击 → 回家
-- 优先级从高到低：
--   1. Leash：超出活动范围时返回出生点
--   2. ChaseAndAttack：发现目标时追击攻击
--   3. Wander：没有目标时在出生点附近游荡
-- 使用 "home" 位置（SetEncounterHermit 中记录的生成位置）作为活动圆心
-- ============================================================================

require("behaviours/chaseandattack")
require("behaviours/leash")
require("behaviours/wander")

-- 行为参数
local MAX_CHASE_TIME = 12        -- 最长追击时间（秒）
local MAX_CHASE_DISTANCE = 30    -- 放弃追击距离
local LEASH_DISTANCE = 24        -- 牵引绳长度：超出此距离开始返回
local RETURN_DISTANCE = 12       -- 返回目标距离：回到此范围内停止返回
local WANDER_DISTANCE = 4        -- 漫游范围

-- ---------------------------------------------------------------------------
-- 获取出生位置（在 SetEncounterHermit 中记录）
-- ---------------------------------------------------------------------------
local function GetHomePosition(inst)
    return inst.components.knownlocations:GetLocation("home")
end

local HermitCrabBossBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

function HermitCrabBossBrain:OnStart()
    -- 行为树根节点（每 0.25 秒重新评估）
    local root = PriorityNode(
    {
        Leash(self.inst, GetHomePosition, LEASH_DISTANCE, RETURN_DISTANCE),
        ChaseAndAttack(self.inst, MAX_CHASE_TIME, MAX_CHASE_DISTANCE),
        Wander(self.inst, GetHomePosition, WANDER_DISTANCE),
    }, 0.25)

    self.bt = BT(self.inst, root)
end

return HermitCrabBossBrain
