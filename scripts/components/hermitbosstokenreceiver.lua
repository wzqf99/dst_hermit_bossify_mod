local TOKEN_PREFAB = "hermitcrab_boss_token"

local HermitBossTokenReceiver = Class(function(self, inst)
    self.inst = inst
    self.received = false
    self.give_task = inst:DoTaskInTime(0, function()
        self.give_task = nil
        self:GiveToken()
    end)
end)

function HermitBossTokenReceiver:GiveToken()
    if self.received or self.inst.components.inventory == nil then
        return
    end

    local token = SpawnPrefab(TOKEN_PREFAB)
    if token == nil then
        return
    end

    self.received = true
    self.inst.components.inventory:GiveItem(token, nil, self.inst:GetPosition())
end

function HermitBossTokenReceiver:OnSave()
    return self.received and { received = true } or nil
end

function HermitBossTokenReceiver:OnLoad(data)
    self.received = data ~= nil and data.received == true
end

function HermitBossTokenReceiver:OnRemoveFromEntity()
    if self.give_task ~= nil then
        self.give_task:Cancel()
        self.give_task = nil
    end
end

return HermitBossTokenReceiver
