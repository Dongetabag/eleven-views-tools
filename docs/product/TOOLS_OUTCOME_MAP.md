# Eleven Views Tools Outcome Map

This map assigns every current `AppFeature` to one primary customer outcome and one exposure tier. The mapping is also encoded exhaustively in `FeatureProductPlacement.swift`, so adding a feature requires an explicit product decision before the app compiles.

## Outcome surfaces

| Outcome | Customer promise | Primary entry point |
|---|---|---|
| Capture | Capture, record, or copy anything useful from the Mac | Capture something |
| Workspace | Prepare the Mac for the work about to happen | Start a workspace |
| Create | Make files and media ready for their destination | Make media ready |
| Meeting | Check camera, microphone, sound, windows, and recording | Meeting check |
| Mac Health | Explain the Mac's condition and recommend safe improvements | Check my Mac |
| Ask Atlas | Let Atlas propose a bounded action with approval and evidence | Ask Atlas |
| Advanced Tools | Keep specialist and higher-risk controls available without making the app intimidating | Advanced Tools |

## Exposure tiers

| Tier | Meaning |
|---|---|
| Primary | Defines the homepage or first-run experience |
| Contextual | Appears inside an outcome, scene, command result, or settings page |
| Advanced | Hidden by default or deliberately enabled by a specialist user |

## Complete 53-feature assignment

| # | Stable feature | Product label | Outcome | Tier | Product role |
|---:|---|---|---|---|---|
| 1 | `switcher` | App switcher | Workspace | Contextual | Move between work apps and windows |
| 2 | `dockPreview` | Dock previews | Workspace | Contextual | Preview windows while moving through a workspace |
| 3 | `dockClick` | Dock click actions | Workspace | Contextual | Control app windows from the Dock |
| 4 | `windowMaximizer` | Window maximizer | Workspace | Contextual | Fit the active window to the current task |
| 5 | `windowLayout` | Window layouts | Workspace | Primary | Arrange repeatable workspaces and future Scenes |
| 6 | `autoQuit` | Auto Quit | Advanced Tools | Advanced | Close inactive apps through an opt-in policy |
| 7 | `scrollInverter` | Scroll direction | Advanced Tools | Advanced | Customize pointer behavior |
| 8 | `focusFollowsMouse` | Focus follows mouse | Advanced Tools | Advanced | Specialist window focus behavior |
| 9 | `smoothScroll` | Smooth scrolling | Advanced Tools | Advanced | Specialist pointer tuning |
| 10 | `mouseNavigation` | Mouse navigation | Advanced Tools | Advanced | Map pointer input to navigation |
| 11 | `mouseButtonShortcuts` | Mouse button shortcuts | Advanced Tools | Advanced | Program specialist pointer actions |
| 12 | `middleClick` | Middle click | Advanced Tools | Advanced | Add specialist pointer behavior |
| 13 | `keyboardDebounce` | Keyboard debounce | Advanced Tools | Advanced | Correct duplicate key input |
| 14 | `textSnippets` | Text snippets | Workspace | Contextual | Reuse common work language |
| 15 | `superKey` | Super Key | Advanced Tools | Advanced | Program a power-user keyboard layer |
| 16 | `clipboardHistory` | Clipboard history | Capture | Primary | Keep copied material available and reusable |
| 17 | `pastePlain` | Paste plain text | Capture | Contextual | Turn copied text into a clean usable artifact |
| 18 | `finderCutPaste` | Finder cut and paste | Workspace | Contextual | Move local work files efficiently |
| 19 | `finderRename` | Finder rename | Workspace | Contextual | Name work artifacts consistently |
| 20 | `shelf` | File Shelf | Capture | Contextual | Hold captured or selected files during a workflow |
| 21 | `urlCleaner` | URL Cleaner | Capture | Contextual | Clean research and source links before reuse |
| 22 | `diskImageInstaller` | Disk image installer | Advanced Tools | Advanced | Install local software through an explicit specialist action |
| 23 | `mixer` | App volume mixer | Meeting | Contextual | Balance app sound before and during calls |
| 24 | `soundOutputSwitcher` | Sound output switcher | Meeting | Contextual | Choose the correct speakers or headphones |
| 25 | `micMute` | Microphone mute | Meeting | Contextual | Make microphone state visible and controllable |
| 26 | `musicBlock` | Music blocking | Workspace | Contextual | Prevent unwanted media during focus or calls |
| 27 | `keepAwake` | Keep awake | Workspace | Contextual | Keep the Mac available for the active scene |
| 28 | `brightness` | Brightness | Workspace | Contextual | Set the display for the current environment |
| 29 | `extraBrightness` | Extra brightness | Advanced Tools | Advanced | Enable a specialist display mode |
| 30 | `quickLauncher` | Quick Launcher | Workspace | Contextual | Open the apps required by a scene |
| 31 | `quickToggles` | Quick Toggles | Workspace | Contextual | Apply common system state changes |
| 32 | `colorPicker` | Color picker | Capture | Contextual | Capture a visual value from the screen |
| 33 | `screenOCR` | Copy text from screen | Capture | Primary | Turn non-copyable screen content into usable text |
| 34 | `cleaningMode` | Cleaning mode | Mac Health | Contextual | Safely prepare hardware for cleaning |
| 35 | `mediaTools` | Media Tools | Create | Primary | Convert, resize, compress, trim, and prepare media |
| 36 | `cleaner` | Cleaner | Mac Health | Primary | Review and recover storage safely |
| 37 | `uninstaller` | Uninstaller | Mac Health | Contextual | Remove apps and related files with review |
| 38 | `homebrew` | Homebrew | Mac Health | Contextual | Review package condition and updates |
| 39 | `appUpdates` | App updates | Mac Health | Contextual | Keep installed apps current |
| 40 | `screenshot` | Screenshot | Capture | Primary | Capture an area, window, page, or display |
| 41 | `cameraPreview` | Camera preview | Meeting | Contextual | Verify the camera before a call or recording |
| 42 | `radialMenu` | Radial Menu | Workspace | Contextual | Reach frequent actions within a scene |
| 43 | `scratchpad` | Scratchpad | Workspace | Contextual | Hold temporary notes during work |
| 44 | `commandBar` | Command Bar | Ask Atlas | Primary | Find manual actions now and governed proposals later |
| 45 | `screenRecorder` | Screen recording | Capture | Primary | Record a real workflow for evidence or Story Studio |
| 46 | `killProcess` | Kill Process | Advanced Tools | Advanced | Stop a process through a deliberate specialist action |
| 47 | `monitorCPU` | CPU | Mac Health | Contextual | Contribute evidence to the health summary |
| 48 | `monitorGPU` | GPU | Mac Health | Contextual | Contribute evidence to the health summary |
| 49 | `monitorMemory` | Memory | Mac Health | Contextual | Contribute evidence to the health summary |
| 50 | `monitorNetwork` | Network | Mac Health | Contextual | Contribute evidence to the health summary |
| 51 | `monitorDisk` | Disks | Mac Health | Contextual | Contribute evidence to the health summary |
| 52 | `monitorPower` | Power | Mac Health | Contextual | Contribute evidence to the health summary |
| 53 | `fanControl` | Fan control | Advanced Tools | Advanced | Expose higher-risk thermal control only to opted-in users |

## Product lifecycle for every capability

```text
Human problem
      ↓
Manual action
      ↓
Shortcut or command
      ↓
Scene candidate
      ↓
Bridge capability candidate
      ↓
Atlas proposal
      ↓
Human approval
      ↓
Bounded execution
      ↓
Verification receipt
      ↓
Measured outcome
```

A feature does not automatically become agent-accessible. Bridge exposure requires its own threat model, allowlist, approval policy, evidence contract, and failure behavior.

## Navigation consequence

The home surface should present six understandable jobs plus Advanced Tools:

1. Capture
2. Workspace
3. Create
4. Meeting
5. Mac Health
6. Ask Atlas
7. Advanced Tools

Settings remains the complete feature catalog. Contextual tools surface inside the relevant job. Advanced tools remain available but do not define the app's perceived complexity.
