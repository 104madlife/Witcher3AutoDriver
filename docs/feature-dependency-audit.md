# AutoDriver 功能与依赖审计

审计日期：2026-10-05。范围：当前源码、规范按键模板、Bootstrap 注册表、原版脚本和已安装的参考 Mod。游戏版本为 `4.0.0.103190(Build Machine)`。

NumPad4 分身漫游和 NumPad5 NPC 镜头功能已经判定开发失败，并从当前实现中移除。下面描述移除后的状态。用户已确认最终精简版本可通过游戏 WitcherScript 编译，当前功能运行正常。

## 1. 当前功能

| 按键 | 当前功能 | AutoDriver 之外的功能依赖 | 主要限制 |
| --- | --- | --- | --- |
| NumPad2 | 已骑马时，让当前坐骑随机移动 | 未发现；使用原版 `ActionMoveTo` | 规范模板和部署合并均覆盖 Horse 与 Horse_Replacer_Ciri |
| NumPad3 | 控制真实玩家随机移动，卡住、到达或超时后换目标 | 未发现；使用原版导航和玩家 AI 行为 | 需要下马；默认速度 1.0 在实现中对应 `MT_FastRun` |
| NumPad6 | 召唤附近马匹并上马，或从当前马匹下马 | 未发现；使用原版骑乘接口 | 战斗、室内、空中、游泳、潜水和船只等状态会阻止上马 |
| NumPad7 | 切换生命无敌，并保护当前背包内有耐久的物品 | 未发现；使用原版无敌和物品能力 | 不修复已有损坏；新物品需要重新开关；氧气只在开启时补充一次 |
| NumPad8 | 每次按键前往下一个官方传送点，支持同世界和跨世界路线 | 未发现；使用原版地图和传送接口 | 包含路牌和港口；跨世界和特殊玩家状态仍待实测 |
| NumPad9 | 先前往当前世界的随机路牌，再寻找附近合法随机落点 | 未发现；使用原版导航、物理和传送接口 | 搜索半径 20–100，最多尝试 20 次；失败时停留在安全路牌处 |

## 2. 已移除功能

| 原按键 | 原功能 | 移除内容 |
| --- | --- | --- |
| NumPad4 | 杰洛特 NPC 分身漫游和静态镜头 | 监听器、处理函数、状态机、分身创建/移动/销毁、镜头跟随、StoryBoardUI 资源加载、按键绑定 |
| NumPad5 | 跟随附近移动 NPC 的镜头 | 监听器、处理函数、状态机、NPC 搜索、原生镜头尝试、静态镜头回退、按键绑定 |
| 无入口 | TunedMovePointWander 与 CustomSeekWander | 状态机、专属参数/进度状态、目标下发函数，以及 `CAutoDriverMoveTRGSeek` |

源码不再加载：

```text
dlc\modtemplates\storyboardui\interactive_camera.w2ent
dlc\modtemplates\storyboardui\geralt_npc.w2ent
```

## 3. 当前依赖

### 硬依赖：Bootstrap

- `CModAutoDriver` 继承 Bootstrap 提供的 `CMod`，并使用它的日志和初始化接口。
- `<game>/mods/modBootstrap-registry/content/scripts/local/mods_registry.ws` 需要包含一次 `add(createAutoDriver());`。
- Bootstrap 脚本会加载 `dlc/modtemplates/bootstrap/bootstrap.w2ent`，因此还需要配套的 `dlcBootstrap` 资源。

### 已解除的依赖

- 当前 AutoDriver 源码和按键模板中没有 StoryBoardUI、RadishSeeds 或 SharedImports 引用。
- 本机共享注册表已经移除 `add(createStoryboardUi());`，只保留 AutoDriver 工厂调用。
- StoryBoardUI、RadishSeeds、SharedImports 及其 DLC 仍安装在本机，但它们不再属于 AutoDriver 的当前依赖。保留这些文件可避免影响其他可能使用它们的 Mod。

这个结论来自静态源码和注册关系。只有在“不安装这些参考 Mod”的环境里成功完成游戏编译，才能把最小依赖组合提升为运行时确认。

## 4. 跨电脑部署注意事项

1. 本机 `mods/modAutoDriver` 已从开发仓库联接转换为真实运行目录，里面只包含打包后的 `mod_autodriver.ws`。跨电脑时应使用同样的发布包结构，不要复制开发仓库或创建目录联接。
2. 仓库已经只保留 `modAutoDriver.input.settings`，其中包含完整的 NumPad8/9 状态覆盖和两种 Horse 状态的 NumPad2。
3. 当前安装历史表明，按键还需要合并进用户目录的 `Documents/The Witcher 3/input.settings`；只放 Mod 内模板不一定生效。
4. 当前没有仓库内独立编译工具，实际编译门槛仍是启动游戏。
5. Bootstrap 0.5 Next-Gen 的完整运行文件已放入 `external/Bootstrap/game-root`，供私有仓库打包和新机器安装使用。

## 5. 建议顺序

1. 在另一台电脑上按 `docs/new-machine-setup.md` 运行完整打包、Dry Run 和部署。
2. 验证最小组合：原版游戏、仓库内 Bootstrap、Bootstrap registry、AutoDriver 和部署脚本合并的用户按键。

## 6. 本次验证

- 已删除 NumPad4/5 的源码入口和全部相关实现。
- 已删除两份模板中的 NumPad4/5 绑定。
- 已备份用户 `input.settings`，并删除其中四条 NumPad4/5 AutoDriver 映射；其他功能对这两个按键的映射保持原样。
- 已删除共享注册表里的 `createStoryboardUi()` 调用。
- 用户已确认移除 NumPad4/5 后游戏脚本编译通过，剩余按键可用。
- 已统一为 `modAutoDriver.input.settings`，补齐 Horse 状态 NumPad2，并删除重复模板。
- 已删除两个无入口的移动实验状态及其专属实现。
- 已用干净 Git 提交生成运行包，并将本机 `modAutoDriver` 联接安全转换为真实运行目录；运行目录只包含一份 `mod_autodriver.ws`。
- 部署后源码与运行文件 SHA-256 均为 `A20F4C751FF931DF75B8C939B9A5C37010855113F68096F90CC404D8B94755BC`，Bootstrap 注册表和用户输入文件哈希在部署前后未变化。
- 静态搜索未发现 AutoDriver 源码、规范按键模板或有效注册表仍引用 StoryBoardUI、分身或镜头动作。
- WitcherScript 花括号数量一致，Git diff 空白检查通过。
- 最终版本已通过用户的游戏编译和当前功能验证。
