# Dirty Frag PoC (CVE-2022-43284)

## Upstream Origin & Purpose
- **Source Origin**: [https://github.com/v4bel/dirtyfrag](https://github.com/v4bel/dirtyfrag)
- **Vulnerability**: XFRM / ESP in UDP socket buffer splice page-cache corruption
- **Source File**: `exp.c` (compiled via `gcc -O2 -Wall -pthread exp.c -o exp`)

## Applied Patches & Justification

1. **Target File Redirection**:
   Hardcoded `TARGET_PATH` directly to the mounted evaluation victim file:
   ```c
   // Original:
   // static const char *get_target_path(void) { ... return "/usr/bin/su"; }
   // #define TARGET_PATH get_target_path()
   
   // Patched:
   #define TARGET_PATH "/mnt/protected/victim_file"
   ```

2. **Suppressed Shell Execution**:
   - Commented out early root shell drop in `main()`, retaining `_exit(1)` as an early-termination guard:
     ```c
     if (getuid() == 0) {
         // PATCH - comment out interactive shell
         // execlp("/bin/bash", "bash", (char *)NULL);
         _exit(1);
     }
     ```
   - Commented out interactive PTY root shell upon successful page-cache patch:
     ```c
     // (void)run_root_pty();
     ```

## Output Contract
The leaf echoes a single marker line on stdout, which `sec/run.sh` resolves into
a verdict (see the [security axis README](../README.md)):
- Marker survived the PoC:
  ```text
  marker=intact
  ```
- Marker overwritten by the PoC:
  ```text
  marker=altered
  ```
Under `pcache_pks=off` an altered marker is the expected real vulnerability
(`PASS`). Under `pcache_pks=on` the neutralization is either an intact marker or
a PKS-attributable kernel panic captured on the serial transcript (`PASS`).

