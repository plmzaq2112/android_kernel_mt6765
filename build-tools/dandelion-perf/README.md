<!-- SPDX-License-Identifier: GPL-2.0 -->
# Dandelion Performance Kernel

绾噣鎬ц兘鍐呮牳 鈥?鍦?4.19.275 BSP 鍩虹涓婂洖绉?5.x 楂樼増鏈唴鏍哥殑楂樻€ц兘鐗规€с€?
## 鐗规€?
| 鐗规€?| 鏉ユ簮鐗堟湰 | 璇存槑 |
|------|----------|------|
| BFQ I/O 璋冨害鍣?| 4.12+ | 鏇村ソ鐨勬闈?绉诲姩 I/O 鍝嶅簲 |
| io_uring | 5.1+ | 楂樻€ц兘寮傛 I/O 妗嗘灦 |
| KSM | 2.6.32+ | 鍐呮牳鍚岄〉鍚堝苟锛岃妭鐪佸唴瀛?|
| THP ALWAYS | 2.6.38+ | 閫忔槑澶ч〉濮嬬粓鍚敤 |
| ZRAM + ZSTD | 3.17+/4.14+ | 鍘嬬缉浜ゆ崲锛孼STD 鍘嬬缉绠楁硶 |
| PSI | 4.20+ | 鍘嬪姏闃诲淇℃伅锛岀簿纭祫婧愮洃鎺?|
| UCLAMP | 5.3+ | CPU 鍒╃敤鐜囬挸鍒讹紝浠诲姟璋冨害浼樺寲 |
| SCHED_AUTOGROUP | 2.6.38+ | 鑷姩杩涚▼鍒嗙粍璋冨害 |
| HZ=1000 | - | 楂樼簿搴﹀畾鏃跺櫒 |
| BBR TCP | 4.9+ | Google 楂樻€ц兘鎷ュ鎺у埗 |

## 涓嶅寘鍚?
- KernelSU (宸茬Щ闄?
- Magisk
- 浠讳綍 root 鏂规

## 鏋勫缓

```bash
# 1. 鏋勫缓鍐呮牳
bash build-tools/dandelion-perf/build.sh

# 2. 鎵撳寘 boot.img
bash build-tools/dandelion-perf/pack.sh

# 3. 鍒峰叆
fastboot flash boot boot-dandelion-perf.img
```

## 閰嶇疆璇存槑

鍩轰簬 `stock_defconfig` + 涓や釜 fragment 鍙犲姞:
1. `boot-4.19.275-perf-v2.config-fragment` 鈥?NR_CPUS=8, 鍏抽棴 MTK sched 鎵╁睍
2. `dandelion-perf.config-fragment` 鈥?鎬ц兘鐗规€?
## 娉ㄦ剰

- 浠呴€傜敤浜?Redmi 9A (dandelion) / MT6765
- 鍒锋満鏈夐闄╋紝璇疯嚜琛屽浠?