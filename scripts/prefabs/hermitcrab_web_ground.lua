-- ============================================================================
-- 铺蛛网地面（Boss 技能）
-- 基于原版 book_web_ground（薇克巴顿铺蛛网法术）改造：
--   - 减速对象从"非玩家"反转为"玩家"，让踩网的玩家减速；
--   - 不影响 Boss 自己（Boss 无 player 标签，天然不受影响）。
-- 生成后可通过 inst.radius / inst.penalty / inst.duration 覆盖默认参数。
-- ============================================================================

local assets =
{
    Asset("ANIM", "anim/fx_book_web.zip"),
    Asset("SOUND", "sound/wickerbottom_rework.fsb"),
}

local DEFAULT_RADIUS = 4
local DEFAULT_PENALTY = 0.3
local DEFAULT_DURATION = 10

-- 只减速玩家，排除幽灵与虚空实体（Boss 无 player 标签，不受影响）。
local SLOWDOWN_MUST_TAGS = { "player" }
local SLOWDOWN_CANT_TAGS = { "playerghost", "INLIMBO" }

local function OnUpdate(inst, x, y, z)
    local radius = inst.radius or DEFAULT_RADIUS
    for i, v in ipairs(TheSim:FindEntities(x, y, z, radius, SLOWDOWN_MUST_TAGS, SLOWDOWN_CANT_TAGS)) do
        if v.components.locomotor ~= nil then
            v.components.locomotor:PushTempGroundSpeedMultiplier(inst.penalty or DEFAULT_PENALTY, WORLD_TILES.MUD)
        end
    end
end

local function OnInit(inst)
    local x, y, z = inst.Transform:GetWorldPosition()

    if inst.task ~= nil then
        inst.task:Cancel()
    end
    inst.task = inst:DoPeriodicTask(0, OnUpdate, nil, x, y, z)
    OnUpdate(inst, x, y, z)

    inst.SoundEmitter:PlaySound("wickerbottom_rework/book_spells/web")
end

local function Despawn(inst)
    inst.AnimState:PlayAnimation("despawn")
    inst:ListenForEvent("animover", inst.Remove)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.Transform:SetRotation(math.random(1, 360))
    inst.Transform:SetScale(1.25, 1.25, 1.25)

    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst:AddTag("NOCLICK")

    inst.AnimState:SetBank("fx_book_web")
    inst.AnimState:SetBuild("fx_book_web")
    inst.AnimState:PlayAnimation("spawn")
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(3)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst.radius = DEFAULT_RADIUS
    inst.penalty = DEFAULT_PENALTY
    inst.duration = DEFAULT_DURATION

    inst:DoTaskInTime(DEFAULT_DURATION, Despawn)
    inst:DoTaskInTime(0, OnInit)

    return inst
end

return Prefab("hermitcrab_web_ground", fn, assets)
