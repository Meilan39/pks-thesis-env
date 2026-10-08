# Copy Fail PoC (CVE-2022-2639)

## Upstream Origin & Purpose
- **Source Origin**: [https://copy.fail/#exploit](https://copy.fail/#exploit)
- **Vulnerability**: AF_ALG splice write out-of-bounds corruption
- **Executable**: `exp` (Python 3 script)

## Applied Patches & Justification

1. **Target File Redirection**:
   Changed the victim file path from `/usr/bin/su` to the mounted evaluation victim file:
   ```python
   # Original:
   # f=g.open("/usr/bin/su",0)
   
   # Patched:
   f=g.open("/mnt/protected/victim_file",0)
   ```

2. **Suppressed Shell Execution**:
   Commented out the interactive shell invocation:
   ```python
   # Original:
   # g.system("su")
   
   # Patched:
   # g.system("su")
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
