name = "寄居蟹隐士 Boss"
description = "将帝王蟹的信物交给寄居蟹隐士，向她发起挑战，胜利后获取珍珠"
author = "夜阑"
version = "0.1.3"

api_version = 10
dst_compatible = true

all_clients_require_mod = true
client_only_mod = false

configuration_options =
{
    {
        name = "boss_health",
        label = "Boss 生命值",
        hover = "设置寄居蟹隐士 Boss 的最大生命值。",
        options =
        {
            { description = "3000（简单）", data = 3000 },
            { description = "5200（默认）", data = 5200 },
            { description = "6000", data = 6000 },
            { description = "9000（困难）", data = 9000 },
            { description = "12000（极难）", data = 12000 },
            { description = "20000（地狱）", data = 20000 },
        },
        default = 5200,
    },
    {
        name = "shell_contacts",
        label = "贝壳碰撞次数",
        hover = "每枚贝壳累计碰撞多少次后破碎（数值越大越难打碎）。",
        options =
        {
            { description = "1 次（易碎）", data = 1 },
            { description = "2 次", data = 2 },
            { description = "3 次（默认）", data = 3 },
            { description = "5 次", data = 5 },
            { description = "10 次（坚固）", data = 10 },
        },
        default = 3,
    },
}
