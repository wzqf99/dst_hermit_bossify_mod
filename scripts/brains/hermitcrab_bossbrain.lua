require("behaviours/chaseandattack")
require("behaviours/leash")
require("behaviours/wander")

local MAX_CHASE_TIME = 12
local MAX_CHASE_DISTANCE = 30
local LEASH_DISTANCE = 24
local RETURN_DISTANCE = 12
local WANDER_DISTANCE = 4

local function GetHomePosition(inst)
    return inst.components.knownlocations:GetLocation("home")
end

local HermitCrabBossBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

function HermitCrabBossBrain:OnStart()
    local root = PriorityNode(
    {
        Leash(self.inst, GetHomePosition, LEASH_DISTANCE, RETURN_DISTANCE),
        ChaseAndAttack(self.inst, MAX_CHASE_TIME, MAX_CHASE_DISTANCE),
        Wander(self.inst, GetHomePosition, WANDER_DISTANCE),
    }, 0.25)

    self.bt = BT(self.inst, root)
end

return HermitCrabBossBrain
