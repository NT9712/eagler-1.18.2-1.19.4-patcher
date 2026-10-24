# Loaded on Windows only (the patcher puts it on PYTHONPATH from Git Bash): makes Python write text like it does on
# Linux, so the build scripts' output files and $(python3 ...) captures are byte-identical (LF, no stray \r).
import builtins, io, sys

_open = builtins.open


def _lf_open(file, mode='r', buffering=-1, encoding=None, errors=None, newline=None, closefd=True, opener=None):
    if newline is None and 'b' not in mode and any(c in mode for c in 'wax+'):
        newline = '\n'
    return _open(file, mode, buffering, encoding, errors, newline, closefd, opener)


builtins.open = _lf_open
io.open = _lf_open
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(newline='\n')
    except Exception:
        pass
