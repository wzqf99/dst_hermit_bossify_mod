-- ============================================================================
-- 胜利后的帝王蟹演出调度。
--
-- 职责：
--   1. 找到天体后羿战场中心那片水面（优先固定点）；
--   2. 在那里生成纯视觉帝王蟹，启动出水演出；
--   3. 演出结束（沉入海底）后回调 encounter，继续发奖与恢复隐士。
--
-- 位置为什么要单独算：
--   玩家指定让帝王蟹从战场海域（红点）钻出，而不是随便找一片海。
--   战场中心在世界观上是固定的（由静态布局决定），但 mod 运行期拿到的
--   hermitcrab_marker 坐标是随岛屿旋转过的，所以要用「marker + 固定偏移」
--   还原那个点，见 tuning.VICTORY_EPILOGUE 的推导注释。
-- ============================================================================

local tuning = require("hermitcrab_boss/tuning").VICTORY_EPILOGUE

local VictoryEpilogue =
{
    PREFABS =
    {
        "hermitcrab_boss_epilogue",
    },
}

-- ---------------------------------------------------------------------------
-- 判断某点是否为可用海面。
-- IsOceanAtPoint(x, y, z, allow_boats)：allow_boats = false 表示"这里不能有船"，
-- 也就是说排除掉已有船只占据的水面，避免演出和玩家的船叠在一起。
-- 注意参数顺序是 (x, y, z)，中间那个 y 是高度，传 0。
-- ---------------------------------------------------------------------------
local function IsFreeOcean(map, x, z)
    return map:IsOceanAtPoint(x, 0, z, false)
end

-- ---------------------------------------------------------------------------
-- 锚点：岛屿几何中心（hermitcrab_marker 的位置）。
-- marker 由 hermitcrab_relocation_manager 放在岛屿中心（原文注释
-- "Place at island center"），必定在陆地上，所以只能当参照原点。
-- ---------------------------------------------------------------------------
local function GetAnchor(inst)
    local center = inst._island_center or inst:GetPosition()
    return center.x, center.z
end

-- ---------------------------------------------------------------------------
-- 首选方案：天体后羿战场中心（固定点）。
--
-- 战场所有摆放物都相对「战场原点」定义，而该原点在 hermitcrab_marker
-- 的 (-14, -22) 处（推导见 tuning 注释）。围绕它先试正中，再试一个小环，
-- 提高命中率的同时仍然严格限制在战场海域内。
-- 找不到可用水面时返回 nil，交给调用方走兜底方案。
-- ---------------------------------------------------------------------------
local function FindArenaPoint(inst)
    local map = TheWorld ~= nil and TheWorld.Map or nil
    if map == nil or map.IsOceanAtPoint == nil then
        return nil
    end

    local cx, cz = GetAnchor(inst)
    -- 默认值与 tuning 保持一致（tuning 缺失时的兜底）。
    local ax = cx + (tuning.ARENA_OFFSET_X or -24)
    local az = cz + (tuning.ARENA_OFFSET_Z or -8)

    -- 正中优先。
    if IsFreeOcean(map, ax, az) then
        return Vector3(ax, 0, az)
    end

    -- 正中不可用（被船占住 / 恰好压在栈桥上）：在固定半径的环上依次试探。
    local radius = tuning.ARENA_SEARCH_RADIUS or 6
    if radius > 0 then
        local steps = 8
        for i = 1, steps do
            local angle = (i - 1) / steps * 2 * math.pi
            local x = ax + math.cos(angle) * radius
            local z = az + math.sin(angle) * radius
            if IsFreeOcean(map, x, z) then
                return Vector3(x, 0, z)
            end
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- 兜底方案：从岛屿中心沿指定方向向外推进，返回第一个海面点。
-- 只在固定点整片区域都不可用时才会走到这里。
-- ---------------------------------------------------------------------------
local function FindFallbackOceanPoint(inst)
    local cx, cz = GetAnchor(inst)
    local map = TheWorld ~= nil and TheWorld.Map or nil

    if map == nil or map.IsOceanAtPoint == nil then
        return nil
    end

    local start = tuning.OCEAN_SEARCH_START or 8
    local step = tuning.OCEAN_SEARCH_STEP or 2
    local maxdist = tuning.OCEAN_SEARCH_MAX or 60
    local base_angle = tuning.OCEAN_SEARCH_ANGLE or -math.pi / 2
    local spread = tuning.OCEAN_SEARCH_SPREAD or 0

    -- 候选方向：主方向优先，失败时向两侧依次偏转。
    local angles = { base_angle }
    if spread > 0 then
        local offsets = { 0.5, -0.5, 1, -1 }
        for _, k in ipairs(offsets) do
            table.insert(angles, base_angle + spread * k)
        end
    end

    -- 方向约定与原版一致（见 brains/pollyrogerbrain.lua FindNearbyOceanPos）：
    --   x 偏移 = dist * cos(角度)，z 偏移 = dist * sin(角度)，不做取负。
    for _, angle in ipairs(angles) do
        local dx = math.cos(angle)
        local dz = math.sin(angle)
        for dist = start, maxdist, step do
            local x = cx + dx * dist
            local z = cz + dz * dist
            if IsFreeOcean(map, x, z) then
                return Vector3(x, 0, z)
            end
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- 解析演出点：优先固定点，失败再兜底。
-- ---------------------------------------------------------------------------
local function ResolvePoint(inst)
    local point = FindArenaPoint(inst)
    if point ~= nil then
        return point
    end

    return FindFallbackOceanPoint(inst)
end

local function OnEpilogueFinished(inst)
    inst._victory_epilogue_actor = nil
end

-- ---------------------------------------------------------------------------
-- 启动演出。
-- @param on_finished 演出彻底结束后的回调（用于继续结算）
-- @return boolean 是否成功启动；false 表示调用方应当直接走正常结算
-- ---------------------------------------------------------------------------
function VictoryEpilogue.Start(inst, on_finished)
    -- 已经有一个在演了：视作已启动，避免重复生成。
    if inst._victory_epilogue_actor ~= nil
        and inst._victory_epilogue_actor:IsValid() then
        return true
    end

    local point = ResolvePoint(inst)
    if point == nil then
        -- 找不到合适海面（地图异常 / 岛屿被改造）。不阻塞结算。
        return false
    end

    local actor = SpawnPrefab("hermitcrab_boss_epilogue")
    if actor == nil then
        return false
    end

    actor.Transform:SetPosition(point.x, point.y, point.z)
    inst._victory_epilogue_actor = actor

    local function finished()
        OnEpilogueFinished(inst)
        if on_finished ~= nil then
            on_finished()
        end
    end

    if actor.StartVictoryEpilogue == nil
        or not actor:StartVictoryEpilogue(finished) then
        inst._victory_epilogue_actor = nil
        if actor:IsValid() then
            actor:Remove()
        end
        return false
    end

    -- 演出期间把已经投降的隐士本体藏起来，画面焦点交给海面。
    inst:Hide()
    if inst.DynamicShadow ~= nil then
        inst.DynamicShadow:Enable(false)
    end
    inst:AddTag("NOCLICK")
    return true
end

-- ---------------------------------------------------------------------------
-- 中断演出（战斗被打断 / 目标消失等）。
-- ---------------------------------------------------------------------------
function VictoryEpilogue.Cancel(inst)
    local actor = inst._victory_epilogue_actor
    inst._victory_epilogue_actor = nil

    if actor ~= nil and actor:IsValid() then
        if actor.CancelVictoryEpilogue ~= nil then
            actor:CancelVictoryEpilogue()
        else
            actor:Remove()
        end
    end
end

return VictoryEpilogue
