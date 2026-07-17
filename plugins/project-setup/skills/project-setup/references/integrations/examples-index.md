# Examples registry — real repos this plugin cites

The skill must **never invent file paths from training data**. When it cites a real-world example, the example comes from this registry — a per-installation list of repos the *user* registers as evidence for the conventions. Registered examples are evidence, not gospel: they evolved at different times with different constraints; cite them, don't blindly copy them.

## Registered examples

None registered yet. When the user names a repo that demonstrates a layout or convention well, add an entry using the template below (ask for the location; record drifts honestly).

```markdown
## <repo-name> — Layout NN (<one-line role>)

**Location**: <absolute or ~ path on this machine>
**Remote** (optional): <URL>

Demonstrates:
- <convention> (<the reference file it evidences>)
- …

Files worth studying:
- `<path>` — <why>

Drifts (where it predates or deviates from current conventions):
- <drift> — do not copy this part
```

## How the skill cites these

When `/ps-setup` (or a single-decision lookup) wants a real-world example:

1. Identify the closest layout / convention area.
2. Cite the **most relevant registered example** and, where possible, a specific file in it.
3. If no registered example covers the pattern: cite the convention from this references library, say plainly that no registered example demonstrates it yet, and propose the pattern on its own merits. **Never fabricate a path or repo.**

## Maintenance

- Add an exemplar when a repo fits a layout cleanly; one entry per repo, honest drift notes.
- Mark aged entries "predates convention X" rather than deleting them.
- Don't migrate the examples to fit the conventions — let them evolve organically, and the citations catch up.
- Registry entries are machine-local (paths are). When this plugin is shared, the registry ships empty; each installation grows its own.
