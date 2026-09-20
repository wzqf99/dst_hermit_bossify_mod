-- ============================================================================
-- 帝王蟹胜利演出实体的状态机。
--
-- 为什么必须有这个 StateGraph：
--   DST 里 AnimState:PlayAnimation 只在本地生效，不会同步给客户端。
--   如果一个实体（尤其是纯视觉实体）在 prefab 里直接调 PlayAnimation，
--   结果就是"服务端以为播了，其他玩家屏幕上什么都没有"。
--   走状态机则 GoToState 会复制状态名，客户端在同样的 onenter 里播同一个
--   动画，所有玩家看到的画面才一致。原版帝王蟹的 reappear / disappear
--   同样由 SGcrabking 驱动。
--
-- 状态流程：
--   inert（水面待机，循环）
--     → reappear（钻出海面）→ inert（说话期间水面待机）→ disappear（沉入海底）
-- ============================================================================

local events = {}

local states =
{
    -- 水面待机：出水前后都用这个状态，帝王蟹保持在水面露头的循环动作。
    State
    {
        name = "inert",
        tags = { "idle", "inert" },

        onenter = function(inst)
            -- 与原版 SGcrabking 的 inert 一致：不显式传 loop，
            -- 由 bank 内该动画自身的循环属性决定。
            inst.AnimState:PlayAnimation("inert")
            -- 原版 inert 里的气泡音效时间轴，让水面待机更有存在感。
            inst.SoundEmitter:PlaySound("hookline_2/creatures/boss/crabking/bubble")
        end,
    },

    -- 钻出海面：播放原版 reappear，并在动画结束时通知逻辑层开始说台词。
    State
    {
        name = "reappear",
        tags = { "idle", "inert", "nointerrupt" },

        onenter = function(inst)
            inst.AnimState:PlayAnimation("reappear", false)
            inst.SoundEmitter:PlaySound("hookline_2/creatures/boss/crabking/appear")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                -- 先回到 inert（由状态机负责，保证客户端同步），
                -- 再通知 prefab 开始说话。
                inst.sg:GoToState("inert")
                inst:PushEvent("epilogue_reappear_done")
            end),
        },
    },

    -- 沉入海底：播放原版 disappear，动画结束后通知逻辑层收尾。
    State
    {
        name = "disappear",
        tags = { "idle", "inert", "nointerrupt" },

        onenter = function(inst)
            inst.AnimState:PlayAnimation("disappear", false)
            inst.SoundEmitter:PlaySound("hookline_2/creatures/boss/crabking/disappear")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                inst:PushEvent("epilogue_disappear_done")
            end),
        },
    },
}

return StateGraph("SGhermitcrab_boss_epilogue", states, events, "inert")
