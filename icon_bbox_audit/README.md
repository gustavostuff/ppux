# Icon Bounding Box Audit

Small standalone LÖVE app that scans `img/icons/` and highlights icons whose
non-transparent pixel bounding box is larger than `7x7`.

The app renders to a `640x360` canvas and presents it at `2x` scale.
UI text uses Proggy (`user_interface/fonts/proggy-tiny.ttf`) when available.

## Run

From repo root:

```bash
love icon_bbox_audit
```

## Controls

- `R`: rescan
- `Esc`: quit
- Mouse wheel: scroll
