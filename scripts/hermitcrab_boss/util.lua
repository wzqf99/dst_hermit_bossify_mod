-- ============================================================================
-- 通用小工具：取消任务、清理实体列表。
-- 多个技能模块共用，消除重复实现。
-- ============================================================================
local Util = {}

-- 取消并清空一个延迟/周期任务；不存在时安全跳过。
function Util.CancelTask(owner, name)
    local task = owner[name]
    if task ~= nil then
        task:Cancel()
        owner[name] = nil
    end
end

-- 移除 inst 上记录的实体数组（如召唤物、环绕物）并清空字段。
-- 逐个做 IsValid 防御，保证任何实体先被移除也不会报错。
function Util.RemoveEntityList(inst, field)
    local list = inst[field]
    if list == nil then
        return
    end

    inst[field] = nil
    for _, entity in ipairs(list) do
        if entity ~= nil and entity:IsValid() then
            entity:Remove()
        end
    end
end

return Util
