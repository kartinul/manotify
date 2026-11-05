# manotify

Native macOS notifications from the command line, written in Swift.

```sh
manotify "Build done"
manotify -t "Deploy failed" -b "main is red" -sf xmark.octagon.fill -c red -g ci
manotify -t "Coffee" -d 10m
choice=$(manotify -t "Ship it?" -A yes:Yes -A no:No --wait)
make 2>&1 | tail -1 | manotify -t "make" -b -
```

## Install

```sh
brew tap kartinul/tap
brew trust --formula kartinul/tap/manotify
brew install --HEAD manotify
```

Or build it yourself: `scripts/bundle.sh` creates `dist/manotify.app`; run `dist/manotify.app/Contents/MacOS/manotify`.

The first send asks for permission. Click **Allow** and leave the command running until you do: killing it while the prompt is up counts as "Don't Allow". If notifications stay off, run `manotify settings` and turn manotify on.

## Icons

- `-sf`, `-c` and `-i` add a thumbnail to a notification.
- The left icon is always the sending app's icon. For a custom one, create a sender once, then send with `-n`:

```sh
manotify sender add ci -sf server.rack -c green --display-name "CI Bot"
manotify -n ci -t "Deploy finished"
```

Each sender is a small app in `~/Library/Application Support/manotify/senders` and asks for permission once. `sender rm` deletes it, but macOS may keep its row in System Settings.

Colors accept `white`, `ffffff`, `'#ffffff'`, `255,0,0` and `'(255,0,0)'`. Quote `#` and `()` forms, since the shell treats them specially.

## Options

| Short | Long | What |
|---|---|---|
| `-t` | `--title` | Title (or pass it as the first argument) |
| `-u` | `--subtitle` | Subtitle |
| `-b` | `--body` | Body; `-` reads stdin |
| `-sf` | `--symbol` | SF Symbol thumbnail |
| `-c` | `--color` | Symbol color |
| `-C` | `--background` | Thumbnail background |
| `-i` | `--image` | Image thumbnail (your file is copied, not moved) |
| `-a` | `--attach` | Extra audio, image or movie attachment |
| `-s` | `--sound` | `default`, `none` or a sound name such as `Glass` |
| `-g` | `--group` | Stack notifications together |
| `-I` | `--id` | Reuse an ID to replace a notification |
| `-l` | `--level` | `passive`, `active`, `time-sensitive`, `critical` |
| `-n` | `--sender` | Send from a sender |
| `-A` | `--action` | Button as `id:Title`, repeatable |
| `-r` | `--reply` | Text reply field with this placeholder |
| `-o` | `--open` | URL or path to open on click |
| `-x` | `--exec` | Shell command to run on click |
| `-w` | `--wait` | Print what the user did: the action ID, `@CLICK`, `@DISMISS` or the reply text |
| `-T` | `--timeout` | Remove after N seconds (implies `--wait`, prints `@TIMEOUT`) |
| `-d` | `--in` | Delay such as `90s`, `5m`, `2h`, `1d` |
| `-j` | `--json` | JSON output |
| `-D` | `--dry-run` | Print the request without sending |

Long-only: `--weight`, `--scale`, `--style`, `--palette`, `--value`, `--clip`, `--thumb-time`, `--no-thumb`, `--relevance`, `--badge`, `--user-info`, `--filter`, `--action-opt`, `--action-icon`, `--report-dismiss`, `--hidden-text`, `--summary`, `--show-hidden-title`, `--activate`, `--at`, `--repeat`, `--every`. See `manotify --help` and `manotify help <command>`.

`--wait` exits 0 for a click or action, 2 when dismissed or timed out, and 1 on error.

Commands: `list`, `remove`/`rm`, `sender add|edit|rm|list`, `auth`, `status`/`doctor`, `settings`.

## Limits

- `time-sensitive` and `critical` need entitlements Apple only grants to paid developer accounts, so this build sends them as normal notifications with a warning.
- Notifications need a logged-in GUI session; they cannot be sent over SSH.
