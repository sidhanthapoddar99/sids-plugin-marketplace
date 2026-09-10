# ctl tooling tests

These tests verify the shipped ctl shell library using temporary environment files. They belong to project-setup itself and are not copied into generated applications.

From the marketplace repository root, with Python 3 and pytest installed:

```sh
python3 -m pytest plugins/project-setup/skills/project-setup/tests/ctl -q
```

No Docker daemon or application dependencies are needed. The tests source the real template library; they do not duplicate its implementation.
