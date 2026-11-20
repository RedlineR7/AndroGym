# Android verification

What has actually been checked on the AndroGym Android build, and what still needs a phone.
Update this file when a device pass runs; keep the date with the result.

## Static checks (done, 2026-11-20)

Built from `freebuff/6135b752ecdd3cf53b7f9223` with JDK 21.0.13, SDK 36, build-tools 36.0.0:

| Check | Result |
|---|---|
| `./gradlew testSideloadDebugUnitTest assembleSideloadDebug` | BUILD SUCCESSFUL, 135 JVM tests, 0 failures |
| `./gradlew assembleSideloadDebug :wear:compileReleaseKotlin` | BUILD SUCCESSFUL |
| APK package | `io.github.redliner7.androgym.test` (debug suffix), versionName 1.4.5 matching `package.json` |
| APK label | `AndroGym Test`; release resources say `AndroGym` |
| SDK levels | minSdk 24, targetSdk 36 |
| Web bundle inside the APK | `opengym-flavor = mobile` (the phone build, not the web app) |
| Updater URL inside the bundle | `RedlineR7/AndroGym` |
| Manifest components | 34 services/receivers/activity-aliases, including `RestTimerService`, `WatchListenerService`, `GymReminderReceiver`, `WorkoutCardReceiver`, `AndroGymWidgetProvider`, and the two Health Connect rationale aliases |
| Permissions | 37 `uses-permission` entries (Health Connect, notifications, location, NFC, camera, microphone) |
| Wear OS module id | `io.github.redliner7.androgym`, the same as the phone app |
| Signed release | `assembleSideloadRelease` with a keystore signs (`apksigner`: `CN=test` in the throwaway run); without one it produces `app-sideload-release-unsigned.apk` |

Not run here: no phone is attached and this VM's `/dev/kvm` is not readable, so an emulator is not
usable. Every item below is owed to a device pass.

## Device checklist

Install with `adb install -r frontend/android/app/build/outputs/apk/sideload/debug/app-sideload-debug.apk`
(debug build, own package), then walk these. Record pass/fail and the date.

- [ ] **First launch:** asks local or server; choosing local reaches Home without a sign-in screen.
- [ ] **Cold start:** boot screen shows instead of a black WebView; no tab bar under the navigation bar, no header under the status bar.
- [ ] **Logging:** a workout, a routine and a weigh-in save; force-stop and relaunch, all three are still there (file mirror, not just WebView storage).
- [ ] **Rest timer:** start a rest, background the app, the countdown notification keeps counting and sounds at zero; lock screen shows it when allowed.
- [ ] **Health Connect:** switch writing on, finish a workout, it appears in Health Connect; the same workout is **not** imported back as an activity.
- [ ] **Backup:** export JSON and export-with-media zip, clear app data, import each; workouts, photos and weigh-ins come back.
- [ ] **Widget:** add the AndroGym widget; it renders; Log set works with the app closed.
- [ ] **Wear OS:** the watch app pairs only with a build of the same id and key; a set logged on the watch reaches the phone.
- [ ] **Gym reminder:** the permission prompt appears only after switching it on; a gym saved with search survives a restart.
- [ ] **Gym search:** OpenStreetMap results appear; the chosen gym keeps its pin and address.
- [ ] **Updates:** Settings → About says there is no update (the fork has no releases yet) without an error.
- [ ] **Signature boundary:** the signed release APK installed over the debug build fails with a signature conflict (expected); installed with the old app removed, it works. AndroGym and an AndroGym signed by another key coexist under their different package ids.
