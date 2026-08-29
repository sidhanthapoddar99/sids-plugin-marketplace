# @scope/styles

The theme. Each app imports exactly one line in its entry file: `import "@scope/styles/globals.css"`.

| File | Holds |
|---|---|
| `tokens.css` | Raw values only. Light on `:root`, dark on `[data-theme="dark"]`. Only colours switch by theme. |
| `globals.css` | Tailwind v4 entry. `@theme` = Tailwind/shadcn default scales. `@theme inline` maps tokens onto `--color-*`, `--radius-*`, `--font-*`. `@source` scans `../../ui/src`. |
| `elements.css` | Base element resets that consume tokens. |

Sizing, spacing and type are Tailwind defaults. No arbitrary values (`p-[13px]`). Only the colour schema is ours.
