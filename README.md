<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/taskley-logo-dark-1560.png">
  <img alt="Taskley" src="docs/taskley-logo-light-1560.png" width="390">
</picture>

[![CI](https://github.com/RadleyRoy/To-Do/actions/workflows/ci.yml/badge.svg)](https://github.com/RadleyRoy/To-Do/actions/workflows/ci.yml)
[![Release](https://github.com/RadleyRoy/To-Do/actions/workflows/release.yml/badge.svg)](https://github.com/RadleyRoy/To-Do/actions/workflows/release.yml)

An **offline-first to-do app for Android**, built with Flutter. All data lives
on your phone in a local SQLite database — no account, no cloud, no tracking.

*created by Radley*

## Features

- **Checklists** — named lists ("Groceries") whose items you can check off and
  un-check.
- **One-time timed tasks** — "Buy milk, tomorrow 18:00", with an optional
  exact alarm.
- **Smart recurring tasks** — two kinds, because not everything repeats the
  same way:
  - **After completion** — "Car Service every 6 months". If you do it late,
    the next one is 6 months from *when you actually did it*.
  - **Fixed schedule** — "Mom's birthday every year". Completing it late
    never shifts the schedule.
- **Notifications** — exactly on time, survive reboots, appear even in Doze
  mode (Android 13+). **Mark done or snooze straight from the notification**
  (15 min, 1 h, 1 day, or 1 week), and set a "remind me before" offset
  (e.g. 1 day before the due date).
- **Home-screen widget** — today's tasks at a glance; taps open the app.
- **Drag-and-drop reordering** — long-press to reorder lists and list items.
- **Backdated completion** — "I actually did this last Tuesday": complete a
  task as of an earlier day, and after-completion recurrence counts from that
  day.
- **Calendar view** — month / 2-week / week formats with dots on busy days
  and a per-day agenda.
- **Subtasks & notes** on any task.
- **Google Calendar import** — one-time migration from an exported `.ics`
  file, fully offline. Yearly events (birthdays) can be imported as
  fixed-schedule recurring tasks. Re-importing never duplicates.
- **Backup / restore** — export everything to a JSON file (save or share),
  restore it on any device.
- **Today / Upcoming** smart views, dark mode, Material 3.

## Getting started

Requirements: [Flutter](https://docs.flutter.dev/get-started/install) 3.44+
(stable) with the Android toolchain. The app targets **Android 13+**
(minSdk 33).

```sh
flutter pub get
dart run build_runner build          # generates Drift database code
flutter run                          # with a device/emulator connected
```

Run the tests and analyzer:

```sh
flutter analyze
flutter test
```

## Importing your Google Calendar

1. On a computer, open [calendar.google.com](https://calendar.google.com)
2. **Settings → Import & export → Export** — downloads a zip
3. Unzip it; each calendar is an `.ics` file
4. Copy the `.ics` file to your phone
5. In Taskley: **Settings → Import from Google Calendar**, pick the file,
   select the events you want, import

## Releases

Tagged releases are built and published automatically by GitHub Actions:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds signed APKs (universal + per-ABI splits) and attaches
them to a GitHub Release. Grab `app-release.apk` (universal) or the
`arm64-v8a` split for modern phones.

### Release signing setup (one-time)

Release builds are signed with a keystore provided via GitHub secrets. Without
the secrets, builds fall back to debug signing (fine for local testing).

1. Generate a keystore (keep it safe; losing it means you can't update the
   installed app). `keytool` ships with the JDK — if it's not on your PATH,
   call it from `<your JDK>\bin\keytool.exe` (Android Studio bundles one at
   `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe`).

   Windows (PowerShell, one line):

   ```powershell
   & "C:\path\to\jdk\bin\keytool.exe" -genkeypair -v -keystore taskley.jks -keyalg RSA -keysize 2048 -validity 10000 -alias taskley -storepass "YOUR_PASSWORD" -dname "CN=YourName"
   ```

   Linux / macOS:

   ```sh
   keytool -genkeypair -v -keystore taskley.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias taskley
   ```

   Modern JDKs create PKCS12 keystores where the key password is the same as
   the store password — use one value for both password secrets below.

2. Add four **repository secrets** (Settings → Secrets and variables →
   Actions):

   | Secret | Value |
   |---|---|
   | `KEYSTORE_BASE64` | the keystore file, base64-encoded — PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("taskley.jks"))`, Linux/macOS: `base64 -w0 taskley.jks` |
   | `KEYSTORE_PASSWORD` | keystore password |
   | `KEY_ALIAS` | `taskley` (or whatever alias you used) |
   | `KEY_PASSWORD` | key password |

For local release builds, create `android/key.properties` (gitignored):

```properties
storeFile=/absolute/path/to/taskley.jks
storePassword=...
keyAlias=taskley
keyPassword=...
```

## Architecture

| Layer | Choice |
|---|---|
| UI | Flutter, Material 3, [Riverpod](https://riverpod.dev) |
| Database | [Drift](https://drift.simonbinder.eu) (SQLite) — reactive streams drive every screen |
| Notifications | flutter_local_notifications with exact alarms (`USE_EXACT_ALARM`), rescheduled after reboot |
| Calendar UI | table_calendar |
| ICS parsing | icalendar_parser |

The recurrence engine (`lib/core/recurrence/recurrence_engine.dart`) is pure
Dart with no Flutter dependencies. Date arithmetic clamps to month ends
(Aug 31 + 6 months → Feb 28/29) and fixed schedules are always computed from
the anchor date so they never drift.

```
lib/
  core/          # database, notifications, recurrence engine, providers
  features/
    lists/       # home + list detail screens
    tasks/       # task editor, task tile, actions
    calendar/    # calendar view
    import_ics/  # Google Calendar import
    backup/      # JSON export/import
    settings/
```

## Roadmap

Ideas for future versions, roughly in priority order:

- [x] Notification actions: **mark done** and **snooze** straight from the alarm *(v0.2.0)*
- [x] "Remind me before" offsets (e.g. 1 day before the due date) *(v0.2.0)*
- [x] Home-screen widget with today's tasks *(v0.2.0)*
- [x] Drag-and-drop reordering *(v0.2.0)*
- [ ] Priorities, tags, and full-text search
- [ ] Statistics: completion streaks, history charts
- [ ] Archive / trash with undo
- [ ] Reusable checklist templates (reset a grocery list with one tap)
- [ ] Voice quick-add
- [ ] Location-based reminders
- [ ] Optional encrypted cloud backup (Google Drive)
- [ ] Shared lists
- [ ] Wear OS tile

## License

[MIT](LICENSE)
