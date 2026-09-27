# GitHub Desk

**Your repos on your desktop.** GitHub Desk tiles up to four GitHub repos,
public or private, on the desktop, the way Hyprland tiles windows. Each tile
shows how the repo is doing at a glance: its numbers, its latest Actions runs,
four weeks of commit activity and its recent commits.

The tiles sit between the wallpaper and your windows, so you see them on an
empty workspace or in the gaps between windows. They never take a click.

## What each tile shows

- **A year of commits** as a heatmap, one column per week like on GitHub, with
  month names, Mon/Wed/Fri and a Less–More legend. Today's cell has a frame
  that breathes, and cells with commits twinkle now and then. The animation
  pauses while windows are open on the workspace, and it can be turned off.
- **The repo:** the owner's avatar recolored in the theme's accent, the name,
  a lock for private repos, the branch shown, and the description.
- **Numbers:** stars, forks, watchers, open pull requests and issues, and the
  latest release.
- **The year in numbers:** all commits, commits in the last year, the current
  streak of days with commits, and the busiest day.
- **Actions:** the last twelve workflow runs as colored blocks, newest on the
  right, and the latest run with its result, duration and age. Green means
  passed, red failed, and yellow running, which pulses.
- **Commits:** short SHA, author, message and time ("today 15:39"), as many as
  fit the tile. A merge commit shows the pull request it merged.
- **A running workflow** takes the commits' place: the run with its number
  and commit, each job with its state and time, and the steps of the job
  that's running, the current one pulsing. Times count up by the second. When
  the run ends, its result (and a failed job's steps) stays for a minute,
  then the commits come back. Several runs at once take turns. The heatmap and
  the repo above stay where they are.

All of it sits on a soft glow in the accent color, and it scales with the
tile: one repo on the whole screen gets big cells and large type.

## Looks like Omarchy

- The tiles use the theme's background (20% opaque by default) and its
  accent color, and they change along with the theme.
- Run colors come from the theme's green, yellow and red.
- The tiles have no border and reach the screen edges. Between tiles is
  Hyprland's gap, and their corners follow its rounding; with rounding off, the
  heatmap cells are square too.
- One repo fills the screen, two sit side by side, three are one large tile
  beside two stacked ones, and four make a 2×2 grid. On a portrait monitor the
  splits turn.

## The icon

The GitHub icon sits in the tray, behind its arrow, and carries a small
status dot for all repos together:

- green when every workflow's latest run passed
- red when any workflow's latest run failed
- yellow while a workflow runs

Click it for the settings. Turn off **Show in the tray** to put the icon on
the bar instead, where it pulses while a workflow runs and a middle-click
refreshes right away.

## Settings

The popup holds everything:

- **Repositories:** up to four. Start typing and it suggests your own repos
  and your organizations' repos, most recently pushed first. Pick one with the
  mouse, or with the arrow keys and Enter. You can also type any `owner/repo`
  or paste a GitHub URL. The branch field is optional; left empty, the tile
  shows the default branch.
- **Opacity** of the tiles.
- **Animations:** the twinkling cells and today's breathing frame.
- **Show in the tray:** the icon behind the tray's arrow, or on the bar.

## Requirements

- The [GitHub CLI](https://cli.github.com/) (`gh`), logged in with
  `gh auth login`. GitHub Desk uses that login, so private repos work without a
  token to set up.
- `jq`, `curl` and the system Python's PyGObject (for the tray icon), which
  Omarchy already has.

## Refreshing

The data is fetched every 5 minutes, and every 30 seconds while a workflow is
running. Changing the repos fetches right away.

The year of commits comes from GitHub's weekly statistics when GitHub has
them ready, which only covers the default branch. Otherwise it's counted from
the history once and then brought up to date with just the newest commits;
a very busy repo takes a while the first time.

The last fetch and the owners' avatars are kept in
`~/.cache/omarchy-github-desk/`, readable only by you, so the tiles come back
immediately after a restart.

## Install

```bash
omarchy plugin add https://github.com/woodenplastic/omarchy-github-desk.git --enable
```

Then click the GitHub icon (behind the tray's arrow) and add your repos.

The tiles only appear on the first monitor, drawn by the widget there. If
you remove the widget from the bar, the tiles go with it.

## Remove

```bash
omarchy plugin remove woodenplastic.github-desk
rm -rf ~/.cache/omarchy-github-desk
```

The first line removes the plugin and its settings; the second deletes the
cached repo data and avatars.

## Permissions

- **Network:** GitHub's API through your `gh` login (repos, commits, Actions
  runs and jobs, your repo list for the suggestions), and the owners' avatars
  from `avatars.githubusercontent.com`.
- **Files:** writes its settings to `~/.config/omarchy/shell.json` through
  Omarchy's `omarchy-shell-config` helper, only when you change them in the
  popup, and its cache to `~/.cache/omarchy-github-desk/`. The tray icons are
  drawn into `$XDG_RUNTIME_DIR/omarchy-github-desk-icons/`.
- **Commands:** `gh`, `jq`, `curl`, and `hyprctl` to read gaps and rounding
  and the cursor position when the tray icon is clicked.
- No root, no tokens of its own, no telemetry.

## Credits

The heatmap, the sparks and the year in numbers follow the look of
[Commit Wallpaper](https://github.com/zenfoco/omarchy-commit-wallpaper) by
zenfoco.

## License

MIT
