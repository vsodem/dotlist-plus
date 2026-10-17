# Routine merge benchmark

Measured on October 17, 2026, on the same Apple M2 running macOS 15.7.7,
Xcode 26.3 and Apple Swift 6.2.4. Baseline: `fc5d93f` (before the merge optimization).

Run `python3 scripts/benchmark-routine-merge.py`. To compare another checkout,
pass `--source-root /absolute/path/to/checkout`. The runner compiles that checkout's
core sources with this benchmark using `-O -whole-module-optimization`, Swift 5,
complete concurrency checking, and warnings as errors. It adds no package targets
or dependencies.

Each case warms up once, then times five complete merges using a monotonic clock.
Fixture construction and result assertions are outside the timed interval. Each
merge includes normal boundary validation; results, conflicts and notices are
checked. Title-only changes rename the middle action locally against an unchanged
base and remote. Cases run in the order shown, before and after on the same machine.
The medians are observations, not CI timing assertions.

| Actions | Case | Before median (ms) | After median (ms) | Improvement |
|---:|---|---:|---:|---:|
| 100 | identical | 4.737 | 0.632 | 7.5× |
| 100 | title-only | 3.949 | 0.607 | 6.5× |
| 500 | identical | 72.551 | 2.939 | 24.7× |
| 500 | title-only | 73.267 | 2.935 | 25.0× |
| 1000 | identical | 291.980 | 5.953 | 49.0× |
| 1000 | title-only | 293.045 | 5.818 | 50.4× |
| 2000 | identical | 1216.097 | 11.982 | 101.5× |
| 2000 | title-only | 1218.129 | 12.157 | 100.2× |

The 2,000-action cases exceed the fivefold target. Matching surviving shared
orders now skip the pairwise ordering graph. Validation reuses lookups, and
addition insertion tracks membership with a set. Differing shared orders still
use the original algorithm; these measurements do not claim a speedup there.

Raw five-run samples (milliseconds):

```csv
actions,scenario,run1_ms,run2_ms,run3_ms,run4_ms,run5_ms,median_ms
100,identical,4.737,5.754,4.894,4.017,4.321,4.737
100,title-only,4.243,3.994,3.949,3.871,3.750,3.949
500,identical,71.996,72.876,73.180,72.396,72.551,72.551
500,title-only,72.103,73.404,73.267,73.242,74.887,73.267
1000,identical,290.555,291.893,291.980,294.765,294.036,291.980
1000,title-only,290.676,293.045,293.565,291.578,293.425,293.045
2000,identical,1216.326,1221.113,1211.703,1201.743,1216.097,1216.097
2000,title-only,1205.473,1199.070,1218.129,1426.430,1230.930,1218.129
```

After:

```csv
actions,scenario,run1_ms,run2_ms,run3_ms,run4_ms,run5_ms,median_ms
100,identical,0.632,0.605,0.604,0.743,0.634,0.632
100,title-only,0.608,0.604,0.606,0.609,0.607,0.607
500,identical,2.929,2.915,3.042,3.058,2.939,2.939
500,title-only,2.935,2.917,3.029,2.943,2.879,2.935
1000,identical,5.953,5.864,5.867,6.073,5.985,5.953
1000,title-only,6.067,5.872,5.818,5.793,5.720,5.818
2000,identical,12.311,12.165,11.982,11.746,11.963,11.982
2000,title-only,12.157,11.877,11.858,12.404,12.351,12.157
```
