-- ============================================================================
-- 信物物品：帝王蟹的信物（漂流瓶外观）
-- 玩家首次进入存档时获得，交给寄居蟹隐士触发 Boss 战
-- 信物不会被消耗，战斗成功触发后立即归还给玩家
-- ============================================================================

local assets =
{
    Asset("ANIM", "anim/bottle.zip"),        -- 漂流瓶动画
    Asset("INV_IMAGE", "messagebottle"),      -- 背包图标：使用漂流瓶的图标
}

-- ---------------------------------------------------------------------------
-- 更新待机动画：在水面上显示水上漂浮，陆地上显示普通
-- ---------------------------------------------------------------------------
local function UpdateIdleAnimation(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    if TheWorld.Map:IsOceanAtPoint(x, y, z, false) then
        inst.AnimState:PlayAnimation("idle_water")
    else
        inst.AnimState:PlayAnimation("idle")
    end
end

-- ---------------------------------------------------------------------------
-- 掉落时重置为普通待机动画
-- ---------------------------------------------------------------------------
local function OnDropped(inst)
    inst.AnimState:PlayAnimation("idle")
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    -- 物品物理 + 水面漂浮
    MakeInventoryPhysics(inst)
    MakeInventoryFloatable(inst, "small", 0.05, 1)

    inst.AnimState:SetBank("bottle")
    inst.AnimState:SetBuild("bottle")
    inst.AnimState:PlayAnimation("idle")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    -- 可检查（右键查看）
    inst:AddComponent("inspectable")

    -- 背包物品组件
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("messagebottle")

    -- 可交易（交给寄居蟹时使用）
    inst:AddComponent("tradable")

    -- 动画切换事件
    inst:ListenForEvent("on_landed", UpdateIdleAnimation)
    inst:ListenForEvent("ondropped", OnDropped)

    -- 鬼魂可作弄
    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("hermitcrab_boss_token", fn, assets)
