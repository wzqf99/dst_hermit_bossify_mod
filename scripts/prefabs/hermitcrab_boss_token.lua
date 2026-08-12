local assets =
{
    Asset("ANIM", "anim/bottle.zip"),
    Asset("INV_IMAGE", "messagebottle"),
}

local function UpdateIdleAnimation(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    if TheWorld.Map:IsOceanAtPoint(x, y, z, false) then
        inst.AnimState:PlayAnimation("idle_water")
    else
        inst.AnimState:PlayAnimation("idle")
    end
end

local function OnDropped(inst)
    inst.AnimState:PlayAnimation("idle")
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)
    MakeInventoryFloatable(inst, "small", 0.05, 1)

    inst.AnimState:SetBank("bottle")
    inst.AnimState:SetBuild("bottle")
    inst.AnimState:PlayAnimation("idle")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("messagebottle")

    inst:AddComponent("tradable")

    inst:ListenForEvent("on_landed", UpdateIdleAnimation)
    inst:ListenForEvent("ondropped", OnDropped)

    MakeHauntableLaunch(inst)

    return inst
end

return Prefab("hermitcrab_boss_token", fn, assets)
