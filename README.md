# Aliases

My personal collection of shell aliases and functions for zsh.

## Tests

```sh
./tests/run_tests.zsh
```

Covers the git and github functions that infer branches. Runs against throwaway
repositories under `TMPDIR` with a fake `HOME` and a stubbed `gh`, so it needs no
network and touches nothing outside its own scratch directory. Pass `KEEP_TMP=1`
to keep that directory for inspection.
