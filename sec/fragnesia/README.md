# Fragnesia PoC (CVE-2026-46300)

- **Source Origin**: [https://github.com/v12-security/pocs/tree/main/fragnesia](https://github.com/v12-security/pocs/tree/main/fragnesia)
- **Vulnerability**: XFRM ESP-in-TCP page-cache replacement
- **Source File**: `exp.c` (compiled via `gcc -O2 -Wall -pthread exp.c -o exp`)

### Modifications Applied

1. **Target File Redirection**:
   Replaced dynamic CLI/environment target resolution in `main()` with a direct call using the mounted evaluation victim file:
   ```c
   // Original:
   // const char *tpath = "/usr/bin/su";
   // if (argc > 1 && argv[1] && argv[1][0]) { ... }
   // file_size = use_existing_target(tpath);
   
   // Patched:
   file_size = use_existing_target("/mnt/protected/victim_file");
   ```

2. **Suppressed Shell Execution**:
   Commented out the final `execve` invocation:
   ```c
   // Original:
   // execve(target_file, NULL, NULL);
   
   // Patched:
   // execve("/usr/bin/su", NULL, NULL);
   ```

3. **Victim File Size Requirement**:
   `collateral-after` mode mandates that `last <= file_size - FRAG_LEN`. For `PAYLOAD_LEN=192` (`last=191`) and `FRAG_LEN=4096`, the target file must be at least 4,288 bytes. `run.sh` prepares a 64 KiB file with trailing zero padding.

