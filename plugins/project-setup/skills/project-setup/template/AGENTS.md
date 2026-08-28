# <project> — agent brief

Read `memory/` before any change. Rules there bind every agent.

## Layout
`apps/` holds every unit. `ctl` is the only entrypoint. See `README.md` for the tree.

## Commands
`ctl setup` · `ctl dev` · `ctl up [+expose|+expose_nginx|+env_override|+traefik]` · `ctl migrate [new "<msg>"]` · `ctl test`

## Exceptions to the standard layout
None.
