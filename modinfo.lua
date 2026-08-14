name = "寄居蟹隐士 Boss"
description = "将帝王蟹的信物交给寄居蟹隐士，向她发起挑战。"
author = "69434"
version = "0.1.0"

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
            { description = "6000（默认）", data = 6000 },
            { description = "5200（原版）", data = 5200 },
            { description = "3000（简单）", data = 3000 },
            { description = "9000（困难）", data = 9000 },
            { description = "12000（极难）", data = 12000 },
            { description = "20000（地狱）", data = 20000 },
        },
        default = 6000,
    },
}
