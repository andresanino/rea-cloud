# targets/

Artifacts to analyze go here and get committed, so cloud sessions (which clone
this repo) can see them: an `.exe`/`.dll`/ELF, an Electron `app.asar` or
extracted tree, an `.apk`, a .NET assembly or `.nupkg`, a firmware image, a
`.pcap`/HAR/SAZ capture, a `.wasm`, a SQLite `.db`.

- One folder per target: `targets/<name>/` with the files and a short
  `NOTES.md` (where it came from, version, what you want to know).
- GitHub rejects files over 100 MB and warns over 50 MB. For big targets use
  Git LFS (`git lfs track "targets/**"`) or attach them to a GitHub Release and
  fetch them in the session with `scripts/fetch-target.sh <name> gh:<owner>/<repo>@<tag>/<asset>`
  (or `/re`). GitHub Release downloads and package registries are reachable
  from cloud sessions; raw file links and arbitrary download URLs usually are not.
- `targets/private/` is git-ignored for local-only artifacts.
- Only commit software you are allowed to analyze.
