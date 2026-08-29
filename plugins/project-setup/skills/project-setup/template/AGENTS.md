# <project> — agent brief

Read `memory/` before any change. Rules there bind every agent.

## Layout
`apps/` holds every unit. `ctl` is the only entrypoint. See `README.md` for the tree.

## Commands
`ctl setup` · `ctl dev [app…] [--proxy]` · `ctl up [+expose_web|+expose|+env_override] [--services a,b]` · `ctl migrate [new "<msg>"]` · `ctl test [app]` · `ctl gate [-q]`

## The gate
Green means `ctl gate` passed. The ladder here: `lint typecheck dead audit test check build e2e`. `clones`, `fuzz`, `perf` run by name at a stage close-out. A recommended rung, once listed here, is never removed.

## Exceptions to the standard layout
None.
