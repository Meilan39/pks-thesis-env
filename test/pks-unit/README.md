# Upstream x86 PKS Architectural Selftest (`pks-unit`)

## Upstream Origin & Purpose
- **Source**: Linux kernel x86 selftest suite, located at [`tools/testing/selftests/x86/test_pks.c`](file:///Users/meilan/Documents/大学/学部卒論/linux-5.18-rc3/tools/testing/selftests/x86/test_pks.c), authored by Intel Corporation.
- **Pristine Verification**: The test file [`test/pks-unit/test_pks.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pks-unit/test_pks.c) is byte-for-byte identical to the upstream kernel source.
- **Role in Thesis**: Validates the low-level hardware and architectural integrity of Protection Keys for Supervisor (PKS) under the evaluated kernel. Before measuring page-cache specific defenses, this test suite ensures that the CPU and kernel properly handle key allocation, thread MSR context switching, and supervisor page faults.

---

## Test Mechanics
The selftest coordinates between a user-space harness and an in-kernel driver enabled by `CONFIG_PKS_TEST=y`. Commands are dispatched by writing numeric commands to `/sys/kernel/debug/x86/run_pks`:

1. `check_defaults` (command `0`): Validates initial MSR IA32_PKRS register permissions and verifies that unallocated supervisor keys default to write-disabled.
2. `single` (command `1`): Allocates a single supervisor key, protects a kernel test allocation, clears the write-disable bit via `pks_update_protection()`, performs a store, and restores protection.
3. `context_switch` (commands `2` and `3`): Arms a key on a parent thread, pins child execution across CPU cores using `sched_setaffinity`, triggers context switches, and asserts that per-thread PKRS state is faithfully preserved across task switches.
4. `exception` (command `4`): Triggers a deliberate supervisor fault to ensure that the exception handling path restores thread protection keys without kernel panics.
5. `exception_update` (command `5`): Verifies fault recovery and key updates within exception callback contexts.

---

## The Upstream Negative Test Case [6] and Evaluation Contract

### The Dynamic Debug Observation
During execution with dynamic debug enabled (`-d`), kernel logs in `dmesg` contain the following output:
```text
pks_test: Test complete [6]: FAIL
```

### Technical Root Cause
In upstream [`lib/pks/pks_test.c`](file:///Users/meilan/Documents/大学/学部卒論/linux-5.18-rc3/lib/pks/pks_test.c#L680), test case 6 corresponds to `RUN_ALL_KEYS`:
```c
#ifdef CONFIG_PKS_TEST_ALL_KEYS
    case RUN_ALL_KEYS:
        sd->last_test_pass = run_all_keys();
        goto unlock_test;
#endif
    default:
        pr_debug("Unknown test\n");
        sd->last_test_pass = false;
        count = -ENOENT;
        break;
```
Because `CONFIG_PKS_TEST_ALL_KEYS` is not enabled in standard x86 kernel configurations, writing 6 returns `-ENOENT` and records `last_test_pass = false`, triggering the dynamic debug message.

The user-space selftest binary handles this gracefully:
```c
if (ret == -ENOENT) {
    printf("[SKIP] Test not supported\n");
    return 0;
}
```
The userspace program exits with return code 0, marking the run as completely successful.

### Applied Patch in Runner
- **Patch Tag**: `# PATCH - evaluate userspace [OK] and exit code 0`
- **Location**: [`test/pks-unit/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pks-unit/run.sh#L40)
- **Rationale**: Earlier testbed versions used a naive string search `grep -q '[FAIL]'` over dynamic debug logs, misclassifying the intentional kernel rejection of test case 6 as a testbed failure. The runner evaluates userspace `[OK]` output and exit code 0, ensuring that hardware selftest results reflect actual CPU capability.

---

## Output Contract & Rollup
- Successful execution:
  ```text
  STATUS node=pks-unit variant=<off|on> verdict=PASS
  ```
- Missing debugfs interface:
  ```text
  STATUS node=pks-unit variant=<off|on> verdict=FAIL note=no_debugfs_trigger
  ```
- Execution failure:
  ```text
  STATUS node=pks-unit variant=<off|on> verdict=FAIL rc=<exit_code>
  ```
