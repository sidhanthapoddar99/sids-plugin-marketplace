# @scope/ui

shadcn-style components. Consumed by `link:` from web and site.
React is a peerDependency so the consumer's copy is the only copy — two Reacts break hooks.
Styles come from `@scope/styles`; components use utilities (`bg-bg-1`, `rounded-md`), never `var(--…)`.
