# Dirty Frag PoC (CVE-2022-43284)

- **Source Origin**: [https://github.com/v4bel/dirtyfrag](https://github.com/v4bel/dirtyfrag)
- **Vulnerability**: XFRM / ESP in UDP socket buffer splice page-cache corruption
- **Source File**: `exp.c` (compiled via `gcc -O2 -Wall -pthread exp.c -o exp`)

### Modifications Applied

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

