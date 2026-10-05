# Copy Fail PoC (CVE-2022-2639)

- **Source Origin**: [https://copy.fail/#exploit](https://copy.fail/#exploit)
- **Vulnerability**: AF_ALG splice write out-of-bounds corruption
- **Executable**: `exp` (Python 3 script)

### Modifications Applied

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
