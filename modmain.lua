-- ============================================================================
-- 寄居蟹隐士 Boss 模组 - 主入口
-- 玩家首次进入存档时获得"帝王蟹的信物"，交给寄居蟹隐士后触发 Boss 战
-- ============================================================================

local STRINGS = GLOBAL.STRINGS
local SpawnPrefab = GLOBAL.SpawnPrefab
local require = GLOBAL.require

-- 自定义物品和生物 prefab 名称
local TOKEN_PREFAB = "hermitcrab_boss_token"
local BOSS_PREFAB = "hermitcrab_boss"
local BOSS_SHELL_PREFAB = "hermitcrab_boss_shell"
local KELP_SPIKE_PREFAB = "hermitcrab_kelp_spike"
local WEB_GROUND_PREFAB = "hermitcrab_web_ground"
local EVENTS = require("hermitcrab_boss/events")
local FINAL_PHASE = require("hermitcrab_boss/skills/final_phase")
local PHASE_SCHEDULER = require("hermitcrab_boss/phase_scheduler")
local TUNING = require("hermitcrab_boss/tuning")

-- 从模组配置读取 Boss 生命值；配置缺失或非法时回退到 tuning 默认值（5200）。
local configured_health = GetModConfigData("boss_health")
if type(configured_health) == "number" and configured_health > 0 then
    TUNING.MAX_HEALTH = configured_health
end

-- 从模组配置读取贝壳碰撞次数；配置缺失或非法时回退到 tuning 默认值（3）。
local configured_shell_contacts = GetModConfigData("shell_contacts")
if type(configured_shell_contacts) == "number" and configured_shell_contacts > 0 then
    TUNING.SHELL_RING.MAX_CONTACTS = configured_shell_contacts
end

-- 注册让游戏加载的 prefab 文件（对应 scripts/prefabs/ 下的同名文件）
PrefabFiles =
{
    TOKEN_PREFAB,
    BOSS_PREFAB,
    BOSS_SHELL_PREFAB,
    KELP_SPIKE_PREFAB,
    WEB_GROUND_PREFAB,
}

-- 房屋默认仍不可攻击；最终阶段只激活本场关联的原版房屋。
FINAL_PHASE.RegisterHousePostInits(AddPrefabPostInit)

-- 物品和生物的名称（鼠标悬停时显示）
STRINGS.NAMES.HERMITCRAB_BOSS_TOKEN = "帝王蟹的信物"
STRINGS.NAMES.HERMITCRAB_BOSS = "寄居蟹隐士"

-- 为所有角色添加检查描述语（右键查看时的文字）
for _, character_strings in pairs(STRINGS.CHARACTERS) do
    if type(character_strings) == "table" and type(character_strings.DESCRIBE) == "table" then
        character_strings.DESCRIBE.HERMITCRAB_BOSS_TOKEN = "瓶中的信物，似乎是写给寄居蟹隐士的。"
        character_strings.DESCRIBE.HERMITCRAB_BOSS = "她认真起来了。"
    end
end

-- ---------------------------------------------------------------------------
-- 检查是否满足开启 Boss 战的条件
-- @param hermit  寄居蟹隐士实体
-- @param giver   手持信物的玩家
-- @return boolean 是否可以开始战斗
-- ---------------------------------------------------------------------------
local function CanStartEncounter(hermit, giver)
    local world = GLOBAL.TheWorld

    -- 只在服务器端执行
    if world == nil or not world.ismastersim then
        return false
    end

    -- 寄居蟹无效
    if hermit == nil or not hermit:IsValid() or hermit:IsInLimbo() then
        return false
    end

    -- 给予者无效或不是玩家
    if giver == nil or not giver:IsValid() or not giver:HasTag("player") then
        return false
    end

    -- 已经给过珍珠（正常交易中获取）或正在开始战斗
    if hermit.pearlgiven or hermit._hermitcrab_boss_starting then
        return false
    end

    -- 该寄居蟹已关联了一个 Boss 实例
    if hermit._hermitcrab_boss ~= nil and hermit._hermitcrab_boss:IsValid() then
        return false
    end

    -- 世界上已存在一个 Boss 实例
    if world._hermitcrab_boss ~= nil and world._hermitcrab_boss:IsValid() then
        return false
    end

    -- 全局搜索确认没有残留的 Boss 标签实体
    if GLOBAL.TheSim:FindFirstEntityWithTag("hermitcrab_boss") ~= nil then
        return false
    end

    -- 寄居蟹正在搬家中（搬迁保护期）
    local relocation_manager = world.components.hermitcrab_relocation_manager
    if relocation_manager ~= nil and not relocation_manager:CanPearlMove() then
        return false
    end

    return true
end

-- ---------------------------------------------------------------------------
-- 启动 Boss 战：将寄居蟹移出场景，在相同位置生成 Boss
-- @param hermit  寄居蟹隐士实体
-- @param giver   触发战斗的玩家
-- @return boolean 是否成功启动
-- ---------------------------------------------------------------------------
local function StartEncounter(hermit, giver)
    if not CanStartEncounter(hermit, giver) then
        return false
    end

    -- 加锁，防止重复触发
    hermit._hermitcrab_boss_starting = true

    -- 记录位置后把寄居蟹移出场景（进入 limbo 状态）
    local x, y, z = hermit.Transform:GetWorldPosition()
    hermit:RemoveFromScene()

    -- 生成 Boss
    local boss = SpawnPrefab(BOSS_PREFAB)
    if boss == nil then
        -- 生成失败：恢复寄居蟹并解锁
        hermit:ReturnToScene()
        hermit._hermitcrab_boss_starting = nil
        return false
    end

    -- 将 Boss 放到寄居蟹原位置
    boss.Transform:SetPosition(x, y, z)

    -- 建立双向引用，用于后续清理和去重检测
    hermit._hermitcrab_boss = boss
    GLOBAL.TheWorld._hermitcrab_boss = boss
    hermit._hermitcrab_boss_starting = nil

    -- 告知 Boss 关联的寄居蟹和挑战者
    boss:SetEncounterHermit(hermit, giver)
    return true
end

-- ---------------------------------------------------------------------------
-- 给所有玩家添加信物发放组件（每名玩家首次进入存档时发放一次）
-- ---------------------------------------------------------------------------
AddPlayerPostInit(function(inst)
    -- 仅在服务器端执行（客户端不需要发放逻辑）
    if not GLOBAL.TheWorld.ismastersim then
        return
    end

    if inst.components.hermitbosstokenreceiver == nil then
        inst:AddComponent("hermitbosstokenreceiver")
    end
end)

-- ---------------------------------------------------------------------------
-- 劫持寄居蟹的交易逻辑：当玩家给予信物时触发 Boss 战
-- ---------------------------------------------------------------------------
AddPrefabPostInit("hermitcrab", function(inst)
    -- 仅在服务器端执行
    if not GLOBAL.TheWorld.ismastersim then
        return
    end

    local trader = inst.components.trader
    if trader == nil then
        return
    end

    -- 保存寄居蟹原有的交易逻辑（正常物品交易不受影响）
    local old_accept_test = trader.test
    local old_on_accept = trader.onaccept

    -- 替换交易检测：如果是信物则走 Boss 战逻辑，否则走原逻辑
    trader:SetAcceptTest(function(hermit, item, giver, count)
        if item ~= nil and item.prefab == TOKEN_PREFAB then
            return CanStartEncounter(hermit, giver)
        end

        return old_accept_test == nil or old_accept_test(hermit, item, giver, count)
    end)

    -- 替换交易执行：信物不消耗，Boss 战成功触发后立即归还给玩家
    trader:SetOnAccept(function(hermit, giver, item, count)
        if item ~= nil and item.prefab == TOKEN_PREFAB then
            if StartEncounter(hermit, giver) then
                -- 战斗成功触发，归还信物（信物可重复使用）
                if item:IsValid() and giver ~= nil and giver.components.inventory ~= nil then
                    giver.components.inventory:GiveItem(item, nil, hermit:GetPosition())
                elseif item:IsValid() and hermit.components.inventory ~= nil then
                    hermit.components.inventory:DropItem(item, true, true)
                end
            elseif item:IsValid() then
                -- 战斗条件不满足，归还信物
                if giver ~= nil and giver.components.inventory ~= nil then
                    giver.components.inventory:GiveItem(item, nil, hermit:GetPosition())
                elseif hermit.components.inventory ~= nil then
                    hermit.components.inventory:DropItem(item, true, true)
                end
            end
            return
        end

        -- 非信物物品走原寄居蟹交易逻辑
        if old_on_accept ~= nil then
            old_on_accept(hermit, giver, item, count)
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- 调试指令：c_sc()
-- 让寄居蟹隐士 Boss 立即释放海带骨刺技能（骨刺牢笼 + 螺旋骨刺），方便测试。
-- 用法：游戏内按 ~ 打开控制台，输入 c_sc() 即可反复触发。
-- ---------------------------------------------------------------------------
GLOBAL.c_sc = function()
    if GLOBAL.TheWorld == nil then
        print("[hermit_bossify] c_sc: 世界未加载")
        return
    end

    -- 客户端输入时转发到服务端执行
    if not GLOBAL.TheWorld.ismastersim then
        GLOBAL.c_remote("c_sc()")
        return
    end

    local boss = GLOBAL.TheSim:FindFirstEntityWithTag("hermitcrab_boss")
    if boss == nil then
        print("[hermit_bossify] c_sc: 未找到寄居蟹隐士 Boss，请先触发 Boss 战")
        return
    end

    -- 清除已触发标志（调度器统一维护互斥，允许反复测试）
    PHASE_SCHEDULER.ResetPhase(boss, EVENTS.KELP_SNARE)
    boss._kelp_snare_released = nil

    -- 触发完整连招流程（先铺蛛网，再施法释放海带骨刺）
    boss:TriggerKelpSnare()
    print("[hermit_bossify] c_sc: 已触发铺蛛网 + 海带骨刺连招")
end
