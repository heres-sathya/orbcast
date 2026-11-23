# Contributing to Orbcast

Thanks for helping. Orbcast stays small on purpose: a fast, free, private recorder for demos. Changes that keep it that way are the easiest to merge.

## Report a bug

[Open an issue](https://github.com/heres-sathya/orbcast/issues/new) with:

- macOS version and Mac model (Apple Silicon or Intel)
- What you did, what you expected, what happened
- A screenshot or short recording if it helps

## Suggest a feature

Open an issue describing the problem first, before the solution. Good fits: anything that makes recording, editing or sharing a demo faster. Poor fits: accounts, cloud services, tracking.

## Submit a change

1. Fork the repo and create a branch: `git checkout -b fix-camera-switch`.
2. Build and test: `./scripts/build.sh && open build/Orbcast.app`.
3. Test the paths you touched: start, pause, resume, restart, stop, export.
4. Keep the style: Swift with AppKit, no new dependencies, small focused files.
5. Open a pull request explaining what changed and how you tested it.

## Code style

- Follow the existing structure (see [docs/architecture.md](docs/architecture.md)).
- Prefer clear names over comments; comment the *why* when it's not obvious.
- UI text is short, plain and sentence case.

By contributing, you agree your work is released under the [MIT License](LICENSE).
