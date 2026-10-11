# PORTING — 移植方法与进展

> 目标设备:Redmi 9A **dandelion / MT6765**,内核源码 4.19 系(MTK + microtrust
> polyvendor 私有改动,与上游 4.19.y 大量冲突)。

## 方法

1. **小步**:每个 -stable 小版本(275→276→277→…→325)单独应用、单独验证,
   不要跨大步。补丁下载:kernel.org `patch-4.19.N.xz`。
2. **应用**:

   ```bash
   xz -dc patches-419-325/patch-4.19.275-276.xz | git apply --check -
   xz -dc patches-419-325/patch-4.19.275-276.xz | git apply -
   git add -A && git commit -S -m "kernels: 4.19.275 -> 4.19.276"
   git tag 4.19.276  # 每个小版本 checkpoint
   ```

   > ⚠️ 这两条命令现在**跑不通**:本地 `kernel-419.275/android_kernel_mt6765-main`
   > 虽然目录名是 275,`Makefile` 里 `SUBLEVEL` 早已是 **325**,275→276 官方增量
   > 套上去会报几百处冲突。275 基线工作树本地已不存在,这段方法只作流程记录;
   > 真要重放,需先从 git 历史里检出 275 基线。

3. **冲突处置**:MTK 私有文件(arch/arm64/boot/dts/mediatek/*、drivers/misc/mediatek/*、
   drivers/star/... microtrust teei/tz)优先保留 vendor 侧,仅吸收上游修复点
   (funct exponential backoff 等);用 `git mergetool` 或手工并置后必跑 `make`.
4. **配置断言**:移植后必须过 `① pure-kernel` 的 `check_config.sh`,
   尤其 **TEE/Keymaster 链不变量**(`CONFIG_TEE=y`、MicroTrust 全系、
   `MTK_SECURE_MEM/MTK_ION_SEC_HEAP/MTK_SEC_VIDEO_PATH_SUPPORT`)与
   **可加载模块支持**(`MODULES/MODULE_UNLOAD/STRICT_MODULE_RWX`)。
   前者断了 ION secure heap 与 SVP 通路直接没,是安全链的**必要条件**;
   但**不是**校园网"密钥过期"的充分条件(见下方"已排除/待验证")。
5. **编译验证**:LLVM 18 + LLD,`O=out-XXXX` 出 `Image.gz` 后走
   `pack_boot.py` 换包。设备验证至少 console 无 panic + SELinux 状态 + TEE probe。
6. **读源工作区的 git**:工作区重整后 `v11ksu/.git` 指针已断,一律用
   `git --no-optional-locks --git-dir=<新路径>/.git --work-tree=<v11ksu>`(见 README),
   否则会顺手写 `worktrees/v11ksu/index`。

## 本地素材(patches-419-325/)

| 文件 | 内容 | 来源/用途 |
|---|---|---|
| `patch-4.19.275-276.xz` | 上游 4.19.276 增量官方补丁 | kernel.org,下一步的基础 |
| `wip-275-276-sync.patch` | 235 文件,+2114/−1669 | ① 共享库 `archive/local-main @6a4cffc7a` 固化件 |
| `wip-325-secure-chain-modules.patch` | 12 文件,+254/−250 | **325 线配置修复固化件**(从 `v11ksu` 未提交改动导出) |

> `wip-275-276-sync.patch` = 从 ① 共享 git 的 WIP 提交导出的补丁,可独立再生
> (`git format-patch -1 archive/local-main --stdout > wip-275-276-sync.patch`,
> sha256 已验证逐字节相同)。
> 用 `git apply --check wip-275-276-sync.patch` 试套,`git apply -R` 可取反。
> **已知瑕疵(记录不改)**:该补丁把 WIP 提交里的备份垃圾
> `arch/arm64/configs/blossom_defconfig.orig-mt6765`(451 行)也一并固化了 ——
> 它忠实于 `archive/local-main`,要消掉得改 ① 侧的历史提交,超出本目录范围。
> **套用前请自行剔除那一段**,否则会在内核树里凭空多出一个 `.orig-*` 文件。
> 需要补齐的中间补丁(276→277→…→325)待网络允许时从 kernel.org 拉,
> 按"方法"逐段放行,**本次本地整理不联网**。

> `wip-325-secure-chain-modules.patch` 是**工作区 diff**(不是 format-patch),
> 导出自 `v11ksu` 相对 `upgrade-325` 的未提交改动。
> 含 `build-tools/boot/dtb` 的二进制删除,所以生成时**必须**带 `--binary`,
> 否则只有一行 `Binary files … differ`,`git apply` 直接拒绝:
>
> ```bash
> # 再生(--git-dir 指主仓库 .git, --work-tree 指 v11ksu; 必须带 --binary)
> git --no-optional-locks --git-dir=<repo>/.git --work-tree=<v11ksu> \
>     diff --binary > kernel-porting/patches-419-325/wip-325-secure-chain-modules.patch
>
> # 试套: git apply 按 **cwd** 解析路径, 必须先 cd 到 v11ksu 根目录;
> #       且必须带 --git-dir/--work-tree —— v11ksu/.git 指针已断,
> #       裸 `git apply` 直接 fatal: not a git repository。
> cd <v11ksu>
> git --no-optional-locks --git-dir=<repo>/.git --work-tree=<v11ksu> \
>     apply --check  kernel-porting/patches-419-325/wip-325-secure-chain-modules.patch
> git --no-optional-locks --git-dir=<repo>/.git --work-tree=<v11ksu> \
>     apply -R --check kernel-porting/patches-419-325/wip-325-secure-chain-modules.patch
> ```
>
> 含 `build-tools/boot/dtb` 的二进制删除,所以生成时**必须**带 `--binary`,
> 否则只有一行 `Binary files … differ`,`git apply` 直接拒绝。
>
> **2026-09-30 重新固化并做真·往返验证**(独立临时 git 仓库,不碰真工作区):
> 正向 `apply --check`(对 index,即 `HEAD` 基线) `rc=0`,
> 反向 `apply -R --check`(对 worktree) `rc=0`;
> 反向后 **12/12** 文件与 `HEAD` 基线逐字节一致,再正向套回后 **12/12** 与
> `v11ksu` 工作区逐字节一致。
>
> ⚠️ **每次改 `v11ksu` 都要重新固化**,否则补丁立刻过期
> (上一版就是 15:07 导出后 15:57/17:28 又改了 3 个文件,导致双向 `--check` 全挂)。

## 进展

| 阶段 | 状态 | 提交/产出 |
|---|---|---|
| 4.19.275 → 4.19.276 | 部分同步(手工合并 wip) | 固化件 `patches-419-325/wip-275-276-sync.patch`(源自 `archive/local-main`) |
| 4.19 → 4.19.325(主线) | 已完成并可构建 | `upgrade-325` 分支,`out-325noksu` |
| 4.19.325 安全媒体链恢复 | **已做**(刷机 #6) | `blossom_defconfig` + `fix11.config` + `check_config.sh`;固化件 `wip-325-secure-chain-modules.patch` |
| 4.19.325 可加载模块支持 `CONFIG_MODULES` | **已做**(刷机 #7) | 同上固化件;`check_config` 24→46 must-y |
| 校园网"密钥过期"根因 | **未定位**,原假设部分证伪 | 详见下方"已排除/待验证" |
| 5.4 / 5.10 / 5.15 | 未开始 | — |

### 325 项目现状(2026-09-29 接手)

`v11ksu` 工作区相对 `upgrade-325` 的**未提交**改动,12 文件 +254/−250:

```
 M README.md                               目录树、KSU 措辞、strip 脚本行为说明
 M arch/arm64/configs/blossom_defconfig    安媒体链 4 项 + TEE 全家 + MODULES 3 项
                                           + 关指纹/NFC;删掉被 Kconfig 丢弃的死行
 M build-tools/BUILD.md                    断言章节扩写(踩坑:断言要断到 Makefile 认的符号)
 M build-tools/build_full.sh               修 set -euo pipefail 吞掉编译失败分支
 M build-tools/check_config.sh             must_y 24→46,新增 must_n 指纹/NFC 4 项,must_eq +1
 M build-tools/fix11.config                新增"可加载模块支持"段;安媒体链段扩为 7 项
 M build-tools/pack_boot.py                默认路径改树相对,去掉过期的 275 家目录硬编码
 M build-tools/strip-selinux-permissive.py v0 也扫 extra_cmdline;verify 覆盖两段并置退出码
 M fs/Kconfig                              去掉重复定义的 IO_URING(.config 逐字节不变)
 D Android.mk                              与 kenv.mk 同批移除,清掉悬空 include
 D build-tools/boot/dtb                    移除原厂 dtb 备份(打包改从 boot.img 现取)
 D kenv.mk                                 移除 MTK Android 编译系统遗留胶水
```

产物链:

| # | 内容 | 产出 | 设备验证 |
|---|---|---|---|
| #6 | 安媒体链恢复 | sha256 `aa62350e…b2af8` | 已刷:三项 `=y` 逐项确认,TEE/Widevine 全通,App **仍报错** |
| #7 | 补 `CONFIG_MODULES` | sha256 `939d1d04…c1df17`,`Image.gz` 10827861 | 已构建,**已被 #8 取代,不再是刷入目标** |
| #8 | 断言扩到 46 项 + 本轮代码/文档修复 | sha256 `533422fd6dc5ef4980a4111242c1b3a03e4df125a03aa80618aa5e01371e948b` | **已刷,当前设备运行中**;镜像与 `builds/sha256.txt` 一致 |
| #9 | 修复后**清编复现验证**(`O=out-325r2`) | sha256 `ec9aa5ebe4d832f22dd6d8c18ccd2b2880ba8ffc0cac3fe2e5611a211c391ca6`,`Image.gz` 10965093 | 已打包逐段校验,**未刷**;同源码复编 `out-325r3` 作非确定性证据 |

> #9:`.config` 与 #8 **sha256 完全相同**(`cee71a24…`)、`check_config` OK(46/11/3)、
> 符号集与 `Image` 大小与 #8 逐字节相同,**但 `Image.gz` sha 不同** ——
> 实测同源码两次清编就已不一致(1330 条全局符号地址漂移),详见
> `build-tools/BUILD.md` §3.2。故核对产物请比 `.config`+`check_config`,别比镜像 sha。

> #8 产物:`C:\Users\31806\Documents\android-kernel\builds\boot-4.19.325-dandelion-perf.img`
> (67108864 bytes)。回滚保险:`C:\Users\31806\Desktop\boot-4.19.275-full-v11.img`。

#7/#8 关键回读(从镜像内 `IKCFG` 抠 `.config`,非看构建目录):
`MODULES/MODULE_UNLOAD/STRICT_MODULE_RWX=y`、安媒体链 4 项 `=y`、
`TEE/KEYMASTER=y`、`KSU/NFC/MICROTRUST_FP_DRIVER` 均 `not set`、
**无 `MODULE_SIG_FORCE`(不会拒载 vendor .ko)**、全镜像 `=m` 计数 **0**、
ramdisk/dtb 与 base 逐字节一致、`ANDROID!` hdr v2 / page 2048。

### "密钥过期"已排除 / 待验证

**已排除**(均在 #6 上实测):

- 时区:原为 `GMT`,已修为 `Asia/Shanghai` 且跨重启保持
- SELinux:`Enforcing`,零条 DRM/Keymaster/TEE/ION 的 avc 拒绝
- WiFi 连通性:已连 `ChinaNet-Young`,`wlan0` 拿到 `100.67.247.22/12`
- TEE/Widevine 运行时:`TEEI_BOOT_OK`、`beanpodkeymaster` 全通、
  `IDrmFactory+widevine` 已注册、`/proc/tmem0` 存在
- **安全媒体链本身**:#6 已恢复 4 项并逐项确认,App 仍报错
- **`CONFIG_MODULES`**:#7 已补(`blossom_defconfig` 第 18 行 `CONFIG_MODULES=y`),
  六份参照实测全 `y`:`arch/arm64/configs/{stock,v11ksu,v11noksu}_defconfig`
  + `kernel-porting/cfgs/{v11_275,ksu43,bootdt}.config`

**待验证**:

1. `pm clear com.cndatacom.jscportal` 后重新登录(已在 #6 上执行,**重登结果未回报**)
2. 4.19.275 → 4.19.325 的内核版本差异(能用的参照 `ksu43` 是 4.19.275)

> 另有 3 项"六份参照 `=y`、本线 `!=y`"但**非安全域依赖**的差异,
> 属有意裁剪,不建议动:`DEBUG_KERNEL`(生产化)、`DEFAULT_CFQ`
> (本线用 BFQ,性能取向)、`SCHED_AUTOGROUP`。

## 注意 / 语录

- 校园网"密钥过期"原先记作"根因 = 内核裁剪关掉安全媒体链" —— **已被 #6 刷机
  实测部分证伪**(链恢复了、App 照报错)。现状见上方"已排除/待验证";
  `check_config.sh` 的断言保留,但它是必要条件,别再当充分条件写死。
- 反向验证断言:`sed` 把任一 must_y 项改成 `is not set` 再跑,必须返回 1。
- **别用 lz4** —— 工作区已全面停用 lz4 依赖。
- **绝不 SIGSTOP**(指纹 HAL 懒启动风暴教训)。
- 每阶段记得 `git worktree` 隔离,避免污染 ① 主战场。升级产物最终并入
  pure-kernel,不留在本仓库。
- **不污染非工作文件夹**:本项目只写 `kernel-porting/` 内;断掉的
  `v11ksu/.git` 指针、`pure-kernel/main` 软链**只记录不修**。