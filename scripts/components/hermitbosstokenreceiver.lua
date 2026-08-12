-- ============================================================================
-- 组件：信物发放器
-- 挂载在玩家身上，首次进入存档时延迟一帧自动发放信物
-- 支持存档：已发放过的玩家不会重复获得
-- ============================================================================

local TOKEN_PREFAB = "hermitcrab_boss_token"

local HermitBossTokenReceiver = Class(function(self, inst)
    self.inst = inst
    self.received = false

    -- 延迟到下一帧执行，确保玩家背包组件已初始化
    self.give_task = inst:DoTaskInTime(0, function()
        self.give_task = nil
        self:GiveToken()
    end)
end)

-- ---------------------------------------------------------------------------
-- 发放信物：仅第一次调用有效
-- ---------------------------------------------------------------------------
function HermitBossTokenReceiver:GiveToken()
    if self.received or self.inst.components.inventory == nil then
        return
    end

    local token = SpawnPrefab(TOKEN_PREFAB)
    if token == nil then
        return
    end

    -- 标记已发放（防止重复）并交给玩家；无法收纳时由原版背包逻辑处理
    self.received = true
    self.inst.components.inventory:GiveItem(token, nil, self.inst:GetPosition())
end

-- ---------------------------------------------------------------------------
-- 存档：记录是否已发放
-- ---------------------------------------------------------------------------
function HermitBossTokenReceiver:OnSave()
    return self.received and { received = true } or nil
end

-- ---------------------------------------------------------------------------
-- 读档：恢复发放状态
-- ---------------------------------------------------------------------------
function HermitBossTokenReceiver:OnLoad(data)
    self.received = data ~= nil and data.received == true
end

-- ---------------------------------------------------------------------------
-- 组件移除时清理定时任务
-- ---------------------------------------------------------------------------
function HermitBossTokenReceiver:OnRemoveFromEntity()
    if self.give_task ~= nil then
        self.give_task:Cancel()
        self.give_task = nil
    end
end

return HermitBossTokenReceiver
