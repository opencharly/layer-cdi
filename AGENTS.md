# AGENTS.md — opencharly/layer-cdi

This repo holds ONE candy: `cdi`, the CDI runtime contract for GPU images. The org rulebook at the
umbrella's root applies; this file adds only what is specific here.

- **The candy removes driver user-space; it never installs it.** Anything that adds
  `libnvidia-*.so*`, `libcuda.so*`, `libcudadebugger.so*` or an `nvidia*` binary to an image is a
  defect this layer exists to catch, not a feature it should tolerate. `libcudart*` and
  `libcudadevrt*` are **not** driver user-space — they are the CUDA toolkit's runtime and compute
  libraries, `layer-cuda` installs and stitches them, and an image that dropped them is broken.
  (The prefix spelling `libcuda*` spans both families and is the mistake opencharly/layer-cdi#6
  fixed.)
- **The ICD JSONs stay.** They name a SONAME, not a version, so the link the injection creates
  satisfies them.
- **The build-time assertion is a `run:`** (see `candy/cdi/charly.yml`): a build container has no
  injection, so a match is unambiguously image content. Never move that enforcement into a `check:`
  that may run GPU-attached.
- The doctrine skill is `.agents/skills/cdi/SKILL.md`; the candy's own is
  `.agents/skills/cdi-layer/SKILL.md`.
