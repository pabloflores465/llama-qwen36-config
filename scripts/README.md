# Compatibility directory

These wrappers preserve the two entry points from the original Qwen 3.6-only
layout. New automation should call `server/start.sh` and `server/stop.sh`.

If a terminal reports `process.cwd` or `getcwd` after a repository migration,
its current directory was deleted while the shell was still inside it. Recover
the terminal once with:

```bash
cd ~/Documents/llama
```

Recreating the pathname cannot repair the deleted directory inode held by an
already-running shell; changing directory does.
