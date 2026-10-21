# planned/ — work not started

Placeholders for two features that are designed but not built. Every file
here is a stub of a few lines; nothing calls them, and they add nothing to
the binary. They are kept apart from the real code so the tree does not
suggest the features exist.

## CPU profiles (`cpu/`)

**The idea:** name a target CPU and have every instruction checked
against what it supports:

```nasm
CPU GENERIC        ; baseline x86-64
CPU SERVER         ; a server feature set
CPU ZEN4           ; AMD Zen 4
CPU SPR            ; Intel Sapphire Rapids
CPU CUSTOM         ; user defined
```

An instruction the profile lacks would be an error (the `E7xx` range).

**What exists instead today:** NASM's `cpu LEVEL` directive works
(`cpu 386`, `cpu p6`, `cpu x64` ... — frontend/syntax `parser_cpu_num`,
encode/x86 `amd64_cpu_forms` with each form's level from
`gen/opcode.s`): an instruction above the level is "no instruction for
this cpu level". Profiles would extend that from levels to named feature
sets (AVX-512 subsets, AMX, APX ...) and errata.

| File | Meant for |
| --- | --- |
| `cpu/cpu.s` | the module's entry |
| `cpu/features.s` | feature flag definitions and validation (the bits are in `include/constant.inc`, *CPU FEATURE BITS*) |
| `cpu/validate.s` | checking one instruction against the profile |
| `cpu/errata.s` | known CPU errata workarounds |
| `cpu/perf.s` | performance hint tables |
| `cpu/profiles/profiles.s` | the profile table |
| `cpu/profiles/generic.s`, `server.s`, `zen4.s`, `spr.s`, `custom.s` | one profile each |

## Self-patching (`selfpatch/`)

**The idea:** utasm rewrites its own hot code at run time from what the
profiler measures (profile/: hot phases, `trigger.s`), validating each
patch and rolling back one that makes things slower.

**Status:** not started; the profiler's trigger only logs that it would
fire, and nothing calls it. It needs executable memory (`mem_alloc_exec`,
`mem_protect` in platform/mem.s, unused until then).

| File | Meant for |
| --- | --- |
| `selfpatch/selfpatch.s` | the engine's entry |
| `selfpatch/patchmap.s` | where patches may go |
| `selfpatch/validate.s` | checking a patch is safe |
| `selfpatch/apply.s` | writing it |
| `selfpatch/rollback.s` | undoing it |
| `selfpatch/log.s` | an audit log of patches |

## Files

Every file is a stub (4-7 lines); what each is meant for is in the tables
above.

| File | Feature |
| --- | --- |
| `cpu/cpu.s`, `cpu/features.s`, `cpu/validate.s`, `cpu/errata.s`, `cpu/perf.s` | CPU profiles |
| `cpu/profiles/profiles.s`, `cpu/profiles/generic.s`, `cpu/profiles/server.s`, `cpu/profiles/zen4.s`, `cpu/profiles/spr.s`, `cpu/profiles/custom.s` | CPU profiles |
| `selfpatch/selfpatch.s`, `selfpatch/patchmap.s`, `selfpatch/validate.s`, `selfpatch/apply.s`, `selfpatch/rollback.s`, `selfpatch/log.s` | self-patching |

## When work starts

Move the folder out of `planned/` to where it belongs (`src/cpu/`,
`src/selfpatch/`), give it a README like every other module, and replace
the stubs as they are written.
