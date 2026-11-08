# GitHub Update — track, update and install your GitHub projects

A bar widget + `zen-gh` helper for [Omarchy](https://omarchy.org/)
(Hyprland/Wayland) that turns every local GitHub checkout into a single,
searchable dashboard:

- **Auto-discovery** — finds every top-level git repo under `$HOME` whose
  origin is on github.com, plus every installed Omarchy shell plugin.
- **Versions & drift** — shows each project's declared version and current
  commit, and how far behind its upstream it is.
- **Update one, or all** — pulls and rebuilds a project (or everything that is
  behind) from the panel; it runs in a floating terminal so you can watch.
- **Install from a URL** — paste a GitHub URL (or `owner/repo`) and it clones,
  follows the repo's own install steps / build system, and adds a launcher and
  menu row. A project is installed once: a repo already present as a checkout or
  as an Omarchy plugin is refused (and shown once in the list).
- **Launch from the panel** — a ▶ button on each app opens it (and opens a
  plugin's panel); the plugin keeps every app's launcher entry in the menu
  alive, creating it if it is missing.
- **Follows the repo's own instructions** — before installing it reads the
  project's README/INSTALL docs and runs the documented command it can verify
  (`./install.sh`, `make install`, `cargo install --path …`, …). Removal runs
  the documented uninstall step first.
- **Reliable plugin activation** — after installing an Omarchy plugin it waits
  for the shell to discover it, uses the right placement, checks that it
  actually turned on, and prints the exact command to run if it did not.
- **Forget / uninstall** — hide a project (keep its files) or fully uninstall
  it, reverting the Omarchy defaults and menu row it added.

  <img width="491" height="703" alt="image" src="https://github.com/user-attachments/assets/937df419-5d5f-4663-afef-b45033fe3fa3" />


Free and open source under the [MIT license](LICENSE). No account, no telemetry.

## Downloads

Grab the latest package from
**[Releases](https://github.com/DanielBeaudryGIThub/github-update/releases/latest)**
(`GitHub-Update-<version>.zip`), or clone this repo. Both contain the same files.

## Requirements

- Omarchy 4.x on Hyprland (Wayland). Other Quickshell/Hyprland setups may work
  with small path changes.
- `git` and `python3` are used by the `zen-gh` helper; `jq` and `gh` are
  optional (used only for a few convenience paths).

## Install

From a release zip:

```bash
cd ~/Downloads
unzip GitHub-Update-<version>.zip
cd GitHub-Update-<version>
./install.sh
```

Or from a clone:

```bash
git clone https://github.com/DanielBeaudryGIThub/github-update.git
cd github-update
./install.sh
```

The installer:

1. copies the plugin and the `zen-gh` helper into `~/.config` / `~/.local`;
2. adds `github-update` to the right side of the Omarchy bar (once — it will
   not duplicate the entry; a `dbeaudry.zengithubupdate` entry from an older
   install is migrated automatically);
3. adds a **GitHub Update** row to the Super+Space menu and refreshes the
   `update.githubapps.*` rows `zen-gh` auto-manages;
4. restarts the Omarchy shell so the widget appears.

The installer is idempotent: re-running it keeps your tracked apps and bar
layout.

## Use

- Click the rabbit icon in the bar, or run `omarchy-shell github-update toggle`.
- **Update all / one** — pull everything behind, or right-click a project.
- **Install** — type a GitHub URL or `owner/repo` and press Enter.
- **Search** — type to filter the list; Enter updates, X uninstalls.
- **Open** — left-click a project to open its repository on GitHub.

## CLI

The panel is a thin view over the `zen-gh` helper:

```bash
zen-gh list-json            # JSON array of tracked apps
zen-gh add <url|owner/repo> # clone/install a GitHub project
zen-gh update <name|id>     # pull (+build/rescan) one project
zen-gh update-all           # update every project that is behind
zen-gh remove <name|id>     # deactivate its Omarchy defaults
zen-gh uninstall <name|id>  # revert config, drop defaults/.desktop/checkout/row
zen-gh sync-menu            # add missing menu rows, prune stale ones
```

Tracked state lives in `~/.config/omarchy/github-update` (ignored/links and
install transactions for safe rollback).

## Uninstall

```bash
./uninstall.sh              # keeps your tracked apps
./uninstall.sh --purge      # also removes the tracked-app state
```

## Project layout

```
install.sh                                  installer (bar + menu)
uninstall.sh                                remover (keeps state by default)
files/.local/bin/zen-gh                     the helper CLI
files/.config/omarchy/plugins/github-update/
    manifest.json                           plugin manifest (author, version)
    Panel.qml                               bar widget / panel UI
scripts/package.sh                          builds the release zip in dist/
scripts/release.sh                          bumps version, builds, tags, publishes
```

## License

MIT — see [LICENSE](LICENSE).
