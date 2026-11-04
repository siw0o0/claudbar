# Claudbar

A KDE Plasma 6 panel widget that shows what your Claude Code sessions are doing: one coloured dot per session, the current session's state, context usage, your plan's 5-hour and weekly limits, and cost. It stays hidden while Claude is closed.

![Claudbar on the panel](docs/panel.png)

![The session list](docs/popup.png)

*Unofficial community project, not affiliated with or endorsed by Anthropic.*

## What it shows

- **Dots**: one per session. Blue means working, orange (blinking) means waiting for your approval, green means done. Finished sessions fade out after 5 minutes; the latest one stays. Click a dot to show that session on the panel.
- **The session on the panel**: its name, state and current tool (`working · Bash · 2 min`), context window usage and cost. By default it shows the most urgent session (approval, then work, then the latest).
- **Limits**: the plan's 5-hour and weekly usage with time to reset.
- **The list** (click the bar): sessions active in the last 10 minutes, at least 3. Click a row to open that chat in the Claude desktop app (through its `claude://code/continue` link; terminal sessions have no chat to open). The buttons on the right of a row pin the session to the panel (click again to unpin) and give it a short name. The **Compact** switch at the bottom hides the bars on the panel and keeps only the percentages (coloured when they pass 80%).

Session names come from the conversation's title (its first meaningful word), or the project folder when there is no title yet.

## How it works

Two parts, both local:

1. **A Claude Code mod** (`mod/`) hooks session events and writes each session's state to `~/.cache/claudbar/sessions/<id>.json` and the plan's limits to `~/.cache/claudbar/usage.json`. It only observes; it never calls the model, so it costs no tokens, and it needs no login or API key.
2. **A Plasma widget** (`plasmoid/`) reads those files. It notices changes by checking file modification times inside Plasma and reads the files with one `awk` call only when something changed. It finds the Claude desktop app through its tray icon on D-Bus and hides when the app quits. Terminal sessions show while they are working or waiting.

Cost is the API-equivalent price Claude Code reports, not what a subscription charges.

## Install

Requirements: KDE Plasma 6, and Claude Code (the CLI or the desktop app's Code tab).

**1. The widget**

```bash
git clone https://github.com/siw0o0/claudbar.git
cd claudbar
./install.sh
```

Then right-click the panel, choose *Add Widgets…*, search for **Claudbar** and drag it onto the panel.

**2. The Claude Code mod**

At the prompt of a terminal session (`claude`):

```
/plugin install claudbar --marketplace siw0o0/claudbar
```

Answer `y` to add the marketplace, then pick the user scope. From a shell instead:

```bash
claude plugin install claudbar --marketplace siw0o0/claudbar
```

In the desktop app, where `/plugin` does not run: click **+** next to the prompt box, then **Plugins**, **Add marketplace** with `siw0o0/claudbar`, then **Add plugin**.

New sessions pick the mod up; restart open ones (or the desktop app) to see them on the panel.

## Uninstall

```bash
./install.sh remove
```

and `/plugin uninstall claudbar` in Claude Code. `~/.cache/claudbar` can be deleted.

## Languages

The interface is in English, with Polish when the system locale is Polish. Translations live in `plasmoid/contents/ui/tr.js`; adding a language is one more catalog there.

## License

MIT
