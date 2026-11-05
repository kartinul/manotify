# manotify

<img src="Resources/AppIcon-preview.png" width="96" alt="manotify icon">

native macos notifications.... from ur terminal.... with everything swift has to offer.

sf symbols, colors, custom images, buttons, text replies, grouping, scheduling, and `--wait` so ur scripts can actually ask you stuff. no electron, no osascript, no "Script Editor wants to send notifications" ahh popups. pure swift, ~20ms a send.

```sh
manotify "build done"
manotify -t "deploy failed" -b "main is red again" -sf xmark.octagon.fill -c red
choice=$(manotify -t "ship it?" -A yes:Yes -A no:No -w)
```

## Install

```sh
brew tap kartinul/tap
brew trust --formula kartinul/tap/manotify
brew install --HEAD manotify
```

or build it urself (needs Xcode or the Command Line Tools):

```sh
scripts/bundle.sh
export PATH="$PWD/dist/manotify.app/Contents/MacOS:$PATH"   # put this in ur ~/.zshrc
```

first send asks for permission, click **Allow**. **don't ctrl-c while that prompt is up**, macos counts it as "Don't Allow" and there's no command to undo it. if it ever gets stuck off: `manotify settings` and flip it on.

## The basics

```sh
manotify "hi"                                   # title only
manotify -t "deploy" -u "prod" -b "v1.2 live"   # title, subtitle, body
manotify -t "ding" -s Glass                     # any sound in /System/Library/Sounds
manotify -t "shh" -s none -l passive            # silent, goes straight to notification center
make 2>&1 | tail -1 | manotify -t make           # piped stdin becomes the body
```

## Make it look good

```sh
manotify -t "hot" -sf flame.fill -c red
manotify -t "hot" -sf flame.fill -c "#ff9500" -C white --weight bold
manotify -t "wifi" -sf wifi --value 0.3
manotify -t "palette" -sf cloud.sun.rain.fill --style palette --palette white --palette yellow --palette cyan
manotify -t "cat" -i ~/Desktop/cat.png
```

colors take whatever u throw at it:

| Form | Example |
|---|---|
| name | `white` `red` `orange` `blue` `mint` `indigo` `pink` ... |
| hex | `fff` `ff9500` `ff950080` `'#ff9500'` |
| rgb | `255,0,0` `'(255,0,0)'` `'rgb(255,0,0)'` |

quote the `#` and `()` ones, ur shell eats them otherwise.

## Custom left icon (senders)

`-sf` and `-i` put the image as a thumbnail on the **right**. the icon on the **left** is always the sending app's icon, macos doesn't let apps change it per notification (i tried the private api too, it gets ignored).

so manotify builds tiny apps with ur icon instead:

```sh
manotify sender add ci -sf server.rack -c green --display-name "CI Bot"
manotify -n ci -t "deploy finished"
```

each sender asks for permission once, then it's instant. `sender list`, `sender edit`, `sender rm` do what they sound like. `sender rm` deletes the app but macos might keep its row in System Settings, nothing i can do about that.

## Buttons, replies, waiting

```sh
choice=$(manotify -t "ship it?" -A yes:Yes -A no:No -w)     # prints yes / no / @CLICK / @DISMISS
reply=$(manotify -t "commit msg?" -r "type here" -w)        # prints what u typed
manotify -t "gone soon" -T 10                               # removes itself after 10s, prints @TIMEOUT
manotify -t "approve?" -A ok:OK -w -j                       # json: {"action": "ok", "id": "..."}
```

| `-w` exit code | Means |
|---|---|
| `0` | clicked or pressed a button |
| `2` | dismissed or timed out |
| `1` | error |

banners only show the first two buttons, macos rule not mine.

## Do stuff on click

```sh
manotify -t "PR ready" -o https://github.com/kartinul/manotify/pulls
manotify -t "download done" -x "open ~/Downloads"
manotify -t "back to work" --activate com.microsoft.VSCode
```

works even after `manotify` exits. macos relaunches it in the background when u click.

## Grouping and replacing

```sh
manotify -t "step 1/3" -g build -I progress
manotify -t "step 2/3" -g build -I progress   # same -I replaces the old one
manotify -t "step 3/3" -g build -I progress
```

`-g` stacks them together in notification center.

## Scheduling

```sh
manotify -t "coffee" -d 10m                # in 10 minutes (90s, 5m, 2h, 1d)
manotify -t "standup" --at 10:00           # next 10:00
manotify -t "release" --at "2026-12-01 09:00"
manotify -t "water" -d 1h --repeat         # every hour
manotify -t "gym" --every tue@18:00        # every tuesday (or daily@18:00)
```

macos holds these, so they fire even if ur terminal is closed.

## Managing

```sh
manotify list                 # pending + delivered (--pending, --delivered, -j)
manotify rm <id>              # or --all
manotify status               # what macos thinks of manotify rn
manotify settings             # opens System Settings > Notifications
manotify -t x -sf bell -D     # dry run, prints the request, sends nothing
manotify help send            # every single flag
```

## All the flags

| Short | Long | What |
|---|---|---|
| `-t` | `--title` | title (or just pass it as the first arg) |
| `-u` | `--subtitle` | subtitle |
| `-b` | `--body` | body (piped stdin is used automatically) |
| `-sf` | `--symbol` | sf symbol thumbnail |
| `-c` | `--color` | symbol color |
| `-C` | `--background` | thumbnail background |
| `-i` | `--image` | image thumbnail (ur file gets copied, not moved) |
| `-a` | `--attach` | extra audio / image / movie, repeatable |
| `-s` | `--sound` | `default`, `none`, or a sound name |
| `-g` | `--group` | stack notifications together |
| `-I` | `--id` | reuse to replace a notification |
| `-l` | `--level` | `passive`, `active`, `time-sensitive`, `critical` |
| `-n` | `--sender` | send from a sender (left icon) |
| `-A` | `--action` | button as `id:Title`, repeatable |
| `-r` | `--reply` | text reply field with this placeholder |
| `-o` | `--open` | url or path to open on click |
| `-x` | `--exec` | shell command to run on click |
| `-w` | `--wait` | wait and print what happened |
| `-T` | `--timeout` | auto remove after N seconds, implies `-w` |
| `-d` | `--in` | delay |
| `-j` | `--json` | json output |
| `-D` | `--dry-run` | print, don't send |

long only, cuz nobody's remembering a letter for these: `--weight` `--scale` `--style` `--palette` `--value` `--clip` `--thumb-time` `--no-thumb` `--relevance` `--badge` `--user-info` `--filter` `--action-opt` `--action-icon` `--report-dismiss` `--hidden-text` `--summary` `--show-hidden-title` `--activate` `--at` `--repeat` `--every`

## How it works

macos only lets **apps** send notifications, a bare cli binary gets rejected. so `manotify` is a cli living inside a tiny hidden `.app` (`LSUIElement`, no dock icon), signed ad-hoc. you run the binary inside the bundle and `UNUserNotificationCenter` treats it like a real app.

| Problem | Fix |
|---|---|
| usernoted rejects bundles launchservices doesn't know about ("Failed to find or validate client") | manotify checks its own registration every run and re-registers itself with `lsregister` |
| `--wait` and click callbacks never arrived | the cli runs off the main thread so `NSApplication`'s run loop stays free for the delegate |
| no public api for a per-notification left icon | senders: generated `.app`s with a rendered `.icns`, the cli `exec`s into them |
| macos *moves* attachment files into its store | manotify hands it a copy so `-i photo.png` doesn't eat ur photo |
| clicks after the cli exited | macos relaunches the bundle with no args, manotify detects that and acts as a responder |
| a stdin left open made scripts hang forever | stdin is only read when it's an actual pipe or file, never a terminal |

## Limits

- `time-sensitive` and `critical` need entitlements apple only gives paid dev accounts. manotify still sends them, just as normal notifications, and warns u.
- needs a logged in gui session, so no sending over ssh.
- macos 13+.

## License

MIT
