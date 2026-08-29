# @scope/ui — the theme and the components, one package

Shared by every frontend that has a sibling. An app imports one line, `import "@scope/ui/globals.css"`, and links one package.

```
src/
├── styles/       tokens.css   raw values: colours (light on :root, dark on [data-theme="dark"]), radius base, fonts, motion
│                 globals.css  the Tailwind v4 entry: @theme = default scales; @theme inline = tokens → utilities; @source ../components
│                 elements.css base element resets that consume tokens
├── components/   shadcn new-york, one file per component, a folder for compound ones
├── lib/utils.ts  cn()
└── index.ts      the public surface
```

Rules
- Sizing, spacing, type and radius are Tailwind / shadcn defaults. No arbitrary values (`p-[13px]`). Only the colour schema is ours.
- A colour is named once, in `tokens.css`, by role (`--bg-1`, `--fg-2`, `--border-1`), never by hue. Components use the utility (`bg-bg-1`), never `var(--…)`, never a hex.
- React and Tailwind are `peerDependencies`: the consumer's copy is the only copy. React is optional so a CSS-only consumer (the Astro docs site) links this package without installing it.
- A single frontend with no sibling keeps this exact `src/` shape inside itself (`src/styles`, `src/components/ui`, `src/lib`). When a second surface appears, that content moves here unchanged.
