<p align="center">
  <img src="docs/design/app-icon.svg" width="128" alt="Lantern icon">
</p>

<h1 align="center">Lantern</h1>

<p align="center"><b>English</b> · <a href="README.md">한국어</a></p>

<p align="center">
  Keep your to-dos in sight, and your Mac awake until the work is done.<br>
  A macOS utility that floats your to-do list in a corner of the screen and keeps your Mac awake while Claude Code or Codex is working (or until a time you choose).
</p>

<p align="center">
  <img src="docs/screenshots/hero.jpg" width="560" alt="Lantern floating in the top-right corner of the desktop">
</p>

> **Note:** The app is currently in Korean only. English support is coming in the next version ([#2](https://github.com/SongKyuSeob/Lantern/issues/2)).

---

## What it does

- **Stay awake**: Keeps your Mac from sleeping for a set time, or until agents like Claude Code and Codex finish their work.
- **Stay awake with the lid closed**: Keeps your Mac awake even when you close the lid without an external display. Turns itself off when the battery runs low or the Mac gets hot.
- **What happens if I close the lid now**: Tells you ahead of time whether your Mac will sleep or stay awake if you close the lid right now.
- **To-dos**: Floats your to-do list in a small window in the top-right corner. It's translucent so it doesn't cover your work, and clicks pass through to whatever is behind it.

<p align="center">
  <img src="docs/screenshots/todo.png" width="300" alt="To-dos tab">
  &nbsp;
  <img src="docs/screenshots/awake.png" width="300" alt="Awake tab: 1 Claude Code task running">
</p>

## Requirements

- macOS 26 or later
- A Mac with Apple silicon (M1 or later). Intel Macs are not supported.
- The internet is used only to check for updates. Once a day, Lantern fetches the latest version info from this repository's GitHub releases. Your to-dos, history and usage are never sent anywhere. You can turn update checks off in Settings.

## Install

1. Download the latest `Lantern-x.y.z.dmg` from the [Releases](../../releases) page.
2. Open the dmg and drag **Lantern** into your **Applications** folder.
3. Open Lantern from the Applications folder.

### If macOS says it "can't be opened"

Lantern is a personal project that isn't signed with an Apple developer certificate yet, so macOS blocks it the first time. Allow it once as below, and it will open normally from then on.

1. Try opening Lantern. When you see "unidentified developer" or "can't be opened", click **Done** (or **Cancel**).
2. Go to **System Settings → Privacy & Security**.
3. Under **Security** near the bottom, you'll see "Lantern was blocked". Click **Open Anyway**.
4. Enter your Mac password, then click **Open** in the dialog that follows.

> If you're not comfortable with this, you can read the code in this repository and build it yourself with Xcode.

> **Before uninstalling, please read [Uninstall](#uninstall) instead of just moving the app to the Trash.** The lid-closed permission (a system rule file) and agent connections stay behind after the app is deleted, so remove them in Settings first.

### Updates

Since 0.3.0, when a new version is out, a small **● New version x.y.z** appears in the top-right window (just a blue dot in single-line view). Open the window and click **Update to x.y.z** at the top to see what's new and install it. You can also check yourself from the menu bar icon's right-click menu → **Check for Updates…** or **Settings → General → Check for Updates**.

- Nothing is installed behind your back. You always click to install.
- Installing restarts Lantern, which ends the current awake session, so Lantern asks first if you're awake. Choose **Install after it ends** to install automatically when the session is over.
- Updates are installed only after their signature is verified.
- **If you're on 0.2.x**, that version has no auto-update. Download the new dmg once and replace the app in your Applications folder. Your to-dos, history and settings are kept.

## Usage

### Menu bar icon

| Icon | Meaning |
|---|---|
| Hollow flame | Awake is off |
| Filled flame | Staying awake |
| Flame with pillars on both sides | Staying awake with the lid closed |

- **Left-click**: Opens or closes the top-right window.
- **Right-click**: Opens the menu, with start/stop awake, Until, Extend, Hide Window, Single-Line View, History, Check for Updates, Settings and Quit.

> On MacBooks, the notch leaves less room in the menu bar, so the Lantern icon can get hidden when you have many icons. **Hold ⌘ and drag the icon to the right**, near the clock, to keep it visible. Even when it's hidden, you can open the window with the shortcut below.

### The top-right window

The window has three looks.

- **Active window**: When you open it with the icon or the shortcut. You can work with your to-dos and awake settings here. It closes when you click outside, or 10 seconds after your mouse leaves it.
- **Resting window**: When the active window closes, it stays as a translucent window showing your awake status and the top three to-dos.
- **Single-line view**: The resting window shrunk to one line, showing only your awake status and the number of to-dos.

<p align="center">
  <img src="docs/screenshots/passive.png" width="300" alt="Resting window">
</p>

Turn single-line view on or off from the menu bar icon's right-click menu → **Single-Line View** (checkmark), or **Settings → General → Show resting window in a single line**. To move the window, **drag the tab row at the top** of the active window to another corner or display; it snaps to the nearest corner when you let go. In a bottom corner, it opens upward. Hovering over the resting window fades it so you can see behind it, and clicks pass through.

### Shortcuts

| Shortcut | Action |
|---|---|
| ⌃⌥L | Open/close the window (same as left-clicking the icon) |
| ⌃⌥⇧L | Hide/show the window |
| Esc | Close the open window |

You can change or turn off shortcuts in **Settings → General → Shortcuts**. Only **combinations with ⌃ or ⌥** are allowed. ⌘ combinations like ⌘W and ⌘C are already used by most apps, and taking them as global shortcuts would block those features in every app.

### Staying awake

In the **Awake** tab of the active window, pick an option under **Until** to start right away.

| Until | Meaning |
|---|---|
| Always | Until you turn it off |
| 1 hour / 2 hours | For that long from now |
| Time | Until the time you pick (tomorrow, if that time has already passed today) |
| Agents | Until your connected agents finish all their work (see [Connecting agents](#connecting-agents)) |

- **Extend ›**: For a timed session, add 30 minutes, 1 hour or 2 hours without restarting.
- **Turn off display**: Turns off the screen right away while keeping the Mac awake.
- Staying awake only prevents sleep when the Mac is left idle. Closing the lid still puts it to sleep. To stay awake with the lid closed, turn on **Stay awake with the lid closed** below.
- When running on battery, awake turns off if the battery drops below the **battery threshold in Settings (20% by default)**.

### Stay awake with the lid closed

Keeps your Mac awake when you close the lid without an external display. Available only while awake is on.

**It needs a one-time permission install.** Go to **Settings → Power → Stay awake with the lid closed**, click **Install…**, and enter your Mac password.

This adds one rule file to your Mac (`/etc/sudoers.d/lantern`) that lets only the three commands below run without a password.

```
sudo /usr/bin/pmset -a disablesleep 1   # prevent sleep
sudo /usr/bin/pmset -a disablesleep 0   # restore sleep
sudo /usr/bin/pmset sleepnow            # sleep now
```

- **Other programs on this Mac can use this rule too.** But all they can do is the three things above: keep the Mac from sleeping, or put it to sleep. Any other command still needs a password.
- You can remove it at any time with **Remove…** in the same place. **The rule file is not deleted along with the app, so please click Remove… before uninstalling Lantern.**

**It turns itself off when**
- the awake session ends (if the lid was closed, the Mac goes to sleep right away)
- the battery drops below the threshold while unplugged
- the Mac gets very hot
- you quit Lantern. Even if Lantern quits unexpectedly, a small watchdog restores the setting within 5 seconds.

> The watchdog shows up as "랜턴 뚜껑 모드 감시" (Lantern lid mode watchdog) under **Login Items & Extensions → App Background Activity** in System Settings. It exists only while staying awake with the lid closed is on.

### Connecting agents

Connect Claude Code and Codex in **Settings → Agents**, and choosing **Agents** under Until keeps your Mac awake only while they're working.

- Connecting adds a Lantern hook to each agent's settings file (Claude Code `~/.claude/settings.json`, Codex `~/.codex/hooks.json`). Nothing else is changed, and the file before the change is kept in the same folder as `.lantern-backup`.
- For **Codex**, reopen Codex after connecting and allow the Lantern entry in the **hook review** that appears (or `/hooks`).
- For **Claude Code**, signals arrive only after you trust the folder you open.
- You can confirm the connection works with "Last signal" in Settings.

**When does Lantern consider the work done?**
- When every working agent has finished, awake turns off after 1 minute. If you give the next instruction in the meantime, it keeps going.
- While a command is running, it waits up to 3 hours even without signals.
- Otherwise, 30 minutes without a signal counts as done. For example, when you stop a task with Esc.
- Closing the agent program counts as done right away.
- If you chose Agents but no agent starts working within 30 minutes, awake turns off.

### To-dos

- In the **To-dos** tab of the active window, type in **Add to-do** and press Enter to add it to the bottom of the list.
- Click the circle to mark it done; it moves to the **Done** group. Click again to bring it back. **Clear** removes only the done items. Cleared to-dos stay in your history.
- Drag to reorder. The top three show in the resting window.
- Double-click to rename, or use the × that appears on hover to remove.
- **Right-click** a to-do for Add Note, Set Due Date, Rename and Remove. Notes and due dates are edited in a small window that pops out to the side (for notes, ⌘Enter saves and Esc cancels).
- To-dos with a note show a small icon next to the title. Click it to expand the full title and the note. Notes are also included in the history window and Markdown copy.
- When you set a **due date**, the date shows on the right side of the row. To-dos that are due soon or overdue turn orange and move to the top of the list. Choose how many days ahead counts as "soon" in **Settings → General → Due soon** (1 day before by default).
- To-dos are stored only on this Mac.

### History

Menu bar icon right-click → **History…**, or **History ›** at the bottom of the To-dos tab.

<p align="center">
  <img src="docs/screenshots/history.png" width="560" alt="History window: a year of activity and records by date">
</p>

- The **activity grid** at the top shows how much you did each day over the year. Use <b>‹ ›</b> to browse previous years. Color it by **completed to-dos** or **awake time**.
- Click a day to see its **completed, removed and awake** records below.
- Filter by **All / Completed / Removed**, or search by to-do title and note.
- **Copy as Markdown** copies that day as a checklist you can paste straight into Obsidian or Notion.

### Settings

Menu bar icon right-click → **Settings…**

| Tab | Contents |
|---|---|
| General | Open at login, single-line view, due soon, updates (auto-check, check now), shortcuts |
| Agents | Connect Claude Code and Codex |
| Power | Battery threshold, lid-closed permission |

## Uninstall

To uninstall cleanly, **before deleting the app**, do these two things in Settings first.

1. **Settings → Power → Stay awake with the lid closed → Remove…** (deletes the permission rule file)
2. **Settings → Agents → Disconnect** (for each connected agent)

Then move Lantern from the Applications folder to the Trash.

### If you already deleted the app

You can clean up manually in Terminal.

```bash
# Remove the lid-closed permission rule (needs your Mac password)
sudo rm /etc/sudoers.d/lantern
# Restore sleep, in case it's still turned off
sudo pmset -a disablesleep 0
# Remove files Lantern left behind (to-dos, signal logs, etc.)
rm -rf ~/Library/Application\ Support/Lantern
rm -f ~/Library/LaunchAgents/com.songkyuseob.lantern.watchdog.plist
```

Lantern hooks left in your agent settings keep writing a small log file every time an agent works, even after the app is deleted (they only record what happened, never conversation content, and stop after 2,000 files). If you removed the folder with `rm -rf ~/Library/Application\ Support/Lantern` above, they do nothing. To remove them from the settings too, delete the entries containing `lantern-agent-hook` from `~/.claude/settings.json` and `~/.codex/hooks.json`, or restore the `.lantern-backup` file in the same folder. Note that the backup is from before connecting, so any settings you changed afterward will be lost.

## Contact

Please report problems or ideas in [Issues](https://github.com/SongKyuSeob/Lantern/issues). For security issues, please use [Security → "Report a vulnerability"](https://github.com/SongKyuSeob/Lantern/security/advisories/new) instead of public Issues.

## License

[MIT](LICENSE)
