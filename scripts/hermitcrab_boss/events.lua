-- ============================================================================
-- 跨模块自定义事件名集中定义。
-- 所有模块统一引用这里的常量，避免散落的裸字符串拼写错误（拼错事件名时
-- 只是静默不触发，极难排查）。
-- ============================================================================
return
{
    -- 战斗生命周期
    ENCOUNTER_FINISHING = "hermitboss_encounter_finishing",
    ENCOUNTER_FINISHED = "hermitboss_encounter_finished",
    SURRENDER = "hermitboss_surrender",

    -- 阶段技能（触发顺序由 phase_scheduler 的阶段表决定）
    GUARD_SUMMON = "hermitboss_guard_summon",         -- 90% 蟹卫召唤
    SHELL_PHASE = "hermitboss_shell_phase",           -- 75% 贝壳环
    KELP_SNARE = "hermitboss_kelp_snare",             -- 50% 海带骨刺
    FINAL_PHASE_STARTED = "hermitboss_final_phase_started", -- 30% 最终阶段开始
    ENTER_FINAL_PHASE = "hermitboss_enter_final_phase",     -- 进入最终阶段动画
}
