# ctl tooling tests

These tests verify the shipped ctl shell library using temporary environment files. They belong to project-setup itself and are not copied into generated applications.

From the marketplace repository root, with Python 3 and pytest installed:

```sh
python3 -m pytest plugins/project-setup/skills/project-setup/tests/ctl -q
```

No Docker daemon or application dependencies are needed. The tests exercise the real template library, setup and conformance workers. Compose rendering tests use the Docker Compose CLI when available and skip explicitly when it is absent. They verify declared container keys, build arguments and process overrides without starting containers.
