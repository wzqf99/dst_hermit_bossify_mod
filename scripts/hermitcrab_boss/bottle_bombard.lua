-- ============================================================================
-- 共享投瓶模块：Boss 第一阶段与房屋阶段共用的漂流瓶投掷 / 爆炸 / 清理原语。
--
-- 原版 messagebottle_throwable 落地只会碎掉，不会造成 Boss 伤害；
-- 这里统一用 complexprojectile 的 OnHit 回调接上自定义爆炸逻辑（伤害归属
-- attacker），避免一阶段与房屋阶段各写一套投瓶代码。
--
-- 注意：绝对不要在瓶子实体上存其他实体引用（如 thrower/house），否则任何
-- 路径触发 JSON 编码时会导致 encode_compliant 递归爆栈。
-- ============================================================================

local BottleBombard = {}

-- ---------------------------------------------------------------------------
-- 瓶子落地爆炸：范围伤害（归属 attacker）+ 特效 + 移除瓶子。
-- @param bottle   瓶子实体
-- @param attacker 伤害归属实体（Boss）；已失效时退化为直接扣血
-- @param params   参数表：{ damage, radius, explode_fx }
-- ---------------------------------------------------------------------------
function BottleBombard.Explode(bottle, attacker, params)
    if bottle == nil or not bottle:IsValid() then
        return
    end

    params = params or {}
    local damage = params.damage or 40
    local radius = params.radius or 2.5

    local x, y, z = bottle.Transform:GetWorldPosition()

    local fx_prefab = params.explode_fx
    if fx_prefab ~= nil then
        local fx = SpawnPrefab(fx_prefab)
        if fx ~= nil then
            fx.Transform:SetPosition(x, y, z)
        end
    end

    local hits = TheSim:FindEntities(x, y, z, radius, { "player" })
    for _, player in ipairs(hits) do
        if player ~= nil
            and player:IsValid()
            and not player:HasTag("playerghost")
            and not player:IsInLimbo()
            and player.components.health ~= nil
            and not player.components.health:IsDead() then
            if attacker ~= nil and attacker:IsValid() and player.components.combat ~= nil then
                -- 伤害归属 attacker（Boss），保证仇恨与击杀统计正确。
                player.components.combat:GetAttacked(attacker, damage, bottle)
            elseif player.components.health ~= nil then
                -- attacker 已失效时的兜底，避免因缺失攻击者而报错。
                player.components.health:DoDelta(-damage)
            end
        end
    end

    bottle:Remove()
end

-- ---------------------------------------------------------------------------
-- 从 thrower 实体位置抛出一个漂流瓶到 aim 落点，落地触发 Explode。
-- @param thrower    起点实体（Boss 或房屋），取其世界坐标 + launch_height
-- @param attacker   伤害归属实体（Boss）
-- @param aim        落点：{ x = , z = }
-- @param params     参数表：{ damage, radius, speed, launch_height, explode_fx }
-- @param guid_field 可选：瓶子 GUID 登记字段名（挂在 attacker 上），nil 不登记
-- @return bottle    瓶子实体（供调用方做进一步处理，可能为 nil）
-- ---------------------------------------------------------------------------
function BottleBombard.Throw(thrower, attacker, aim, params, guid_field)
    if thrower == nil or not thrower:IsValid() or aim == nil then
        return nil
    end

    local bottle = SpawnPrefab("messagebottle_throwable")
    if bottle == nil then
        return nil
    end

    params = params or {}
    local launch_height = params.launch_height or 2.5
    local speed = params.speed or 12

    local sx, sy, sz = thrower.Transform:GetWorldPosition()
    sy = sy + launch_height

    bottle.Transform:SetPosition(sx, sy, sz)
    bottle:AddTag("NOCLICK")
    bottle:AddTag("hermitboss_bottle")
    if bottle.components.inventoryitem ~= nil then
        bottle.components.inventoryitem.canbepickedup = false
    end

    -- 登记 GUID（挂在 attacker 上），用于统一清理。
    if guid_field ~= nil and attacker ~= nil and attacker:IsValid() then
        attacker[guid_field] = attacker[guid_field] or {}
        local guid = bottle.GUID
        table.insert(attacker[guid_field], guid)
        bottle:ListenForEvent("onremove", function()
            local guids = attacker[guid_field]
            if guids ~= nil then
                for i, g in ipairs(guids) do
                    if g == guid then
                        table.remove(guids, i)
                        break
                    end
                end
            end
        end, bottle)
    end

    -- 使用原版 complexprojectile 组件发射：自带抛物线轨迹、飞行旋转动画
    -- （spin_loop），落地必然触发 OnHit，不会再出现手写 SetPosition 与物理
    -- 组件冲突导致"飞到了却不爆炸"。
    local projectile = bottle.components.complexprojectile
    if projectile ~= nil then
        projectile:SetOnHit(function(proj, atk, target)
            -- atk 是 Launch 时传入的 attacker（Boss）。
            BottleBombard.Explode(proj, atk or attacker, params)
        end)
        projectile:SetHorizontalSpeedForDistance(
            math.sqrt((aim.x - sx) * (aim.x - sx) + (aim.z - sz) * (aim.z - sz)),
            speed
        )
        projectile:Launch(Vector3(aim.x, 0, aim.z), attacker)
        -- 关闭碰撞：直飞目标落点，不被树/建筑等障碍物挡下。
        if bottle.Physics ~= nil then
            bottle.Physics:SetCollides(false)
        end
    end

    return bottle
end

-- ---------------------------------------------------------------------------
-- 清理某实体上 GUID 登记表中的所有瓶子。
-- @param inst  持有登记表的实体（Boss）
-- @param field 登记字段名（如 "_bottle_toss_guids" / "_final_bottle_guids"）
-- ---------------------------------------------------------------------------
function BottleBombard.CleanupGuids(inst, field)
    if inst == nil or field == nil then
        return
    end
    local guids = inst[field]
    inst[field] = nil
    if guids ~= nil then
        for _, guid in ipairs(guids) do
            local bottle = Ents[guid]
            if bottle ~= nil and bottle:IsValid() then
                bottle:Remove()
            end
        end
    end
end

return BottleBombard
