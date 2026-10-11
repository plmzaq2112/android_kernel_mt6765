# kernel-porting — 向高版本内核移植

目的:把 dandelion(MT6765) 的 4.19.275 + MTK/微宏私有改动逐级搬到更高版本内核。

现状(2026-09-30):

- 已收录补丁:`patches-419-325/patch-4.19.275-276.xz`(4.19.276 -stable 增量)
- 已有一次 `4.19.275 → 4.19.276` 的**不完整同步**尝试,成果保存在
  ① pure-kernel 共享 git 的 `archive/local-main` 分支
  (提交 `6a4cffc7a` "wip: partial 4.19.275->276 sync",供参考勿删)
- 主线已独立推进到 **4.19.325**(在 ① pure-kernel 的 `upgrade-325` 分支),
  `out-325noksu` 即其产物
- 325 线的配置修复(**安全媒体链** + **可加载模块支持**)与本轮代码/文档修复
  已固化为 `patches-419-325/wip-325-secure-chain-modules.patch`
  (12 文件 +254/−250,源自 `v11ksu` 工作区,截至 2026-09-30 **尚未提交**;
  已做正反向 `--check` + 临时仓库逐字节往返验证,见 `PORTING.md`)
- 参照配置已落盘 **`cfgs/`**(此前散在临时目录,会被清理工具清掉)
- ⚠️ 工作区 2026-09-29 13:53–14:31 被重整:① 主战场
  `10-kernel-419/android_kernel_mt6765-main` 已改名为
  `kernel-419.275/android_kernel_mt6765-main`,但 `v11ksu/.git` 与
  `pure-kernel/main` 仍指旧路径 → 在 `v11ksu/` 里跑 `git` 会 fatal。
  **本项目不代为修复**(只在本目录内动手);要读 325 线的 git 请绕过指针:

  ```bash
  git --no-optional-locks \
      --git-dir=/home/a12bbb/android-kernel/kernel-419.275/android_kernel_mt6765-main/.git \
      --work-tree=/home/a12bbb/android-kernel/v11ksu status --short
  ```

  `--no-optional-locks` 必须带上,否则 git 会顺手刷新 `worktrees/v11ksu/index`。
  跑 `git apply` 时还必须**先 `cd` 进 `v11ksu`** —— git apply 按 cwd 解析路径。

## 目录

```
kernel-porting/
├── README.md          本文件
├── PORTING.md         方法与进展记录
├── cfgs/              参照配置快照(只读对照,不参与构建)
│   └── bootdt.config  ksu43.config  ours6.config  v11_275.config
└── patches-419-325/   4.19.x 补丁集
    ├── patch-4.19.275-276.xz   上游官方增量
    ├── wip-275-276-sync.patch  本线 275→276 部分同步 WIP 固化件
    └── wip-325-secure-chain-modules.patch  325 线配置修复固化件
```

## 路线

1. **存量路线(4.19 内)**:按 patch-4.19.x-4.19.y.xz 顺序逐段 `git apply`;
   每段留 checkpoint tag。vendor(meditek) 与 microtrust/teei 私有符号
   往往与上游冲突,需人工并置。
2. **未来路线(5.x)**:目标 5.4 → 5.10 → 5.15;单步跨越过大时先走
   `4.19 → 5.4` 的过渡补丁再逐级。
3. 移植产物最终并入 ① pure-kernel 的构建线(blossom_defconfig + build_full.sh 断言)。

详见 `PORTING.md`。