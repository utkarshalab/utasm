# profile/ — `--profile`: where the time goes

`utasm --profile prog.s` (or `-P`) prints, on stderr after assembling, how
many CPU cycles each phase of utasm took, measured with the time-stamp
counter. This README is also the profiler's design document; the code's
comments point here.

## What is measured

The timestamps are taken at phase transitions (`profiler_start_phase`,
`profiler_end_phase`), each phase one entry (`PROFENTRY`, struc in
`include/type.inc`: its cycles, call count, start / end TSC, hot flag):

| Phase (`PHASE_*`) | Timed around | Where |
| --- | --- | --- |
| `PARSER` | every `parser_parse_instruction` call — which pulls its tokens through the preprocessor and the lexer, so their time is in it | main/utasm.s |
| `ENCODER` | every instruction's encoding | main/utasm.s |
| `LINKER` | `reloc_resolve_all` | link/linker.s |
| `OUTPUT` | writing the output file | link/linker.s |
| `TOTAL` | from `profiler_init` to `profiler_finalize` | profiler.s |

`PHASE_LEXER`, `PHASE_PREPROCESSOR` and `PHASE_SEMANTIC` exist (and slots
for 56 sub-phases, `MAX_PROF_ENTRIES` 64) but are not timed separately:
their work happens inside the parser's calls.

## How it measures

- **Start**: `LFENCE; RDTSC`, inlined in `profiler_start_phase` (no call
  overhead), so earlier instructions finish before the stamp.
- **End**: `RDTSCP` first, then the bookkeeping (so validating the entry
  is not counted), `LFENCE` after (rdtsc.s).
- **Calibration** (`rdtsc_calibrate`, at `profiler_init`): an empty
  start / end pair timed 1,024 times, the minimum kept; that cost is subtracted from every
  measurement (`calib_overhead`) and shown in the footer. The rdtsc
  wrappers use no prologue / epilogue macros, so they do not inflate it.
- **Accumulated**: each phase's deltas add up over its calls; the call
  count and the average per call are reported.

## The report

`profiler_finalize` takes the end stamp, sums the cycles, marks **hot**
phases (`hotpath_detect`: more than `PROF_HOT_THRESHOLD`, 10 M cycles ≈
3.3 ms at 3 GHz) and sorts them hottest first (`hotpath_rank`: insertion
sort — at most 64 entries, all in L1). `profiler_report` prints a table:
borders, title, column headers (phase, cycles, %, calls, average), one row
per phase (`profiler_print_row`, `[HOT]` marked), the total, and a footer
with the legend, the calibration overhead and the wall-clock time.

## The self-patch trigger (`trigger.s`)

Meant to hand hot phases to the self-patching engine
(`src/planned/selfpatch/`). That engine does not exist, so the trigger
only logs that it would have fired — and nothing calls it yet.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `profiler.s` | 233 | `profiler_init` (memory, entries, calibration, start stamp), `profiler_finalize` |
| `phase.s` | 162 | `profiler_start_phase`, `profiler_end_phase` |
| `rdtsc.s` | 124 | `rdtsc_read`, `rdtsc_read_end`, `rdtsc_calibrate` |
| `state.s` | 103 | `global_profstate` and accessors |
| `hotpath.s` | 73 | `hotpath_detect` |
| `rank.s` | 149 | `hotpath_rank`, `hotpath_get_top` |
| `report.s` | 207 | `profiler_report` |
| `table.s` | 161 | the header and one row |
| `fmt.s` | 233 | numbers with separators, percentages, right alignment |
| `strings.s` | 152 | every string the report prints |
| `trigger.s` | 174 | the self-patch trigger (not called) |

## Entry points

| Symbol | Used by |
| --- | --- |
| `profiler_init`, `profiler_finalize`, `profiler_report` | main/utasm.s |
| `profiler_start_phase`, `profiler_end_phase`, `global_profstate` | main/utasm.s, link/linker.s |

Unused today: `profiler_get_entry`, `profiler_get_state`,
`profiler_get_total_cycles`, `profiler_is_enabled`, `hotpath_get_top`,
`profiler_trigger_check`.

## Depends on

main/ (`print_str`), lib/arena.s.

## What is left

Timing the lexer, preprocessor and semantic phases on their own (they
need start / end calls at their boundaries, inside the parser's pull),
sub-phases (an instruction class, a directive), and the self-patch
trigger once `src/planned/selfpatch/` exists.

## Tests

`tests/run_profiler.sh` builds and runs `tests/unit/profiler/test_profiler.s`
(calibration, phases, ranking, the report).
