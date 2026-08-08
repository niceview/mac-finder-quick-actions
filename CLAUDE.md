# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An installer for three macOS Finder integrations. There is no build step and no test framework — `install.sh` generates artifacts into the live system, so the only meaningful test is installing and exercising them.

## Architecture

`install.sh` is the only entry point and must work **two ways**: run from a clone, or piped (`curl … | bash`). When piped, `BASH_SOURCE[0]` is not a readable file, so the script cannot find `src/` next to itself and downloads the repo tarball into a temp dir instead. Anything that assumes a checkout exists on disk will silently break the one-liner — test both paths (`./install.sh` and `cat install.sh | bash`).

There is exactly **one `mktemp -d` and one `EXIT` trap**, at the top. A second `trap … EXIT` anywhere replaces the first and leaks the temp dir; reuse `$WORK/<subdir>` instead.

`src/` holds **templates**, not finished artifacts. `install.sh` copies them into place and substitutes three tokens:

| Token | Becomes |
|---|---|
| `__HERDR__` | Absolute path to the `herdr` binary, resolved per machine |
| `__TERM_APP__` | Terminal app name (default `Ghostty`) |
| `__MENU_LABEL__` | The string shown in Finder's right-click menu |

Substitution runs through an inline Python heredoc in `install.sh` (`substitute()`), not `sed`, because the values contain `/` and the labels are non-ASCII.

A `.workflow` bundle is just `Contents/Info.plist` + `Contents/document.wflow` — Automator's GUI is not needed to author one. `Info.plist` declares the Service (`NSMessage: runWorkflowAsService`, `NSSendFileTypes: public.item`, restricted to `com.apple.finder`); `document.wflow` carries a single `com.apple.RunShellScript` action whose `ActionParameters.COMMAND_STRING` holds the actual shell script, with `inputMethod: 1` meaning "pass input as arguments" (`$@`). If you need to know the valid parameter keys for an Automator action, read `/System/Library/Automator/<Action Name>.action/Contents/Info.plist`.

The droplet (`src/herdr-droplet.applescript`) exists because **Finder's sidebar right-click menu never shows Services/Quick Actions** — that is a macOS limitation with no workaround. A droppable app is the only way to act on a sidebar item.

## Constraints that are easy to break

**Directory names in `src/` must stay ASCII.** macOS stores filenames decomposed (NFD), so a Korean directory name in git causes normalization problems. Korean lives only inside `Info.plist` string values. Installed bundles are likewise ASCII-named (`Open in VS Code.workflow`); the menu label comes from `NSMenuItem.default`, not the bundle name.

**Brace every shell variable followed by a multibyte character.** `"$VAR」"` makes bash parse the multibyte bytes as part of the variable name and fail with `unbound variable` under `set -u`. Write `"${VAR}」"`. This already bit this repo once.

**Never ship a prebuilt `.app`.** The droplet is compiled with `osacompile` on the target machine to avoid Gatekeeper quarantine on a transferred bundle. After swapping in a custom icon you must also `rm Contents/Resources/Assets.car` and delete `CFBundleIconName` from `Info.plist` — either one takes precedence over `droplet.icns` and the icon silently won't change. Re-run `codesign --force --deep -s -` after touching bundle resources.

**Missing dependencies must skip, not abort.** VS Code, herdr, and Ghostty are each optional; `install.sh` installs whatever it can and reports the rest under 건너뜀. Three rules hang off this:

- A dependency that disappeared takes its previously installed artifact with it (`drop_stale()`), reported under 제거됨 — a menu item whose binary is gone does nothing when clicked, which is worse than its absence.
- `pbs -flush` / `killall Finder` only run when something was actually installed or removed. Never restart Finder for a no-op.
- If nothing was installed, print guidance to stderr and `exit 1`. Exiting 0 makes a fully failed install look successful to any caller.

When testing these paths, note that `PATH=/usr/bin:/bin bash install.sh` really does delete your working artifacts — that is the intended behavior, so reinstall afterwards.

This repo is public. Keep personal paths and internal config out of it.

## Verifying a change

```sh
bash -n install.sh uninstall.sh          # syntax
./uninstall.sh && ./install.sh           # full round trip; run install twice to check idempotency
plutil -lint "$HOME/Library/Services/Open in Herdr.workflow/Contents/"*   # both plists must lint
```

Confirm the Services actually registered (expect exactly one line per workflow — duplicates mean a stale bundle was left behind):

```sh
/System/Library/CoreServices/pbs -dump_pboard | grep "NSBundlePath.*Services"
```

Confirm every token was substituted:

```sh
grep -c "__HERDR__\|__TERM_APP__\|__MENU_LABEL__" "$HOME/Library/Services/Open in Herdr.workflow/Contents/"*   # expect 0
osadecompile "$HOME/Applications/Herdr.app" | grep -c "__"                                                      # expect 0
```

Exercise the artifacts without touching the mouse:

```sh
automator -i "$HOME/Downloads" "$HOME/Library/Services/Open in Herdr.workflow"
open -a "$HOME/Applications/Herdr.app" "$HOME/Music"      # same code path as a Finder drop
```

For the VS Code workflow, `automator` returns 0 whether or not anything opened. Check that the folder actually landed in VS Code's recent list instead of trusting the exit code:

```sh
grep -o "<folder-name>" "$HOME/Library/Application Support/Code/User/globalStorage/storage.json"
```

## Testing against a live herdr session

`herdr workspace create --focus` steals the user's focus, and every test leaves a real workspace behind. Always clean up:

```sh
herdr workspace list                    # JSON; read ids from .result.workspaces[].workspace_id
herdr workspace close <id>
herdr workspace focus w1                # return the user to where they were
```

`herdr --skill` prints the tool's own agent-facing documentation — read it before guessing at subcommands.

Note that `install.sh` and `uninstall.sh` both run `killall Finder`.
