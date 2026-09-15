# Local Thaw fixes

Branch: `codex/trigger-ordering`, based on upstream release commit `72afeb2e`.

- Restore the pointer after every move, regardless of cursor visibility settings.
- Use bounded trigger attempts and preserve failure latches through transient snapshots.
- Poll system and image conditions every second without overlapping work.
- Preserve trigger ownership during profile restoration.
- Recognize parked windows with contradictory WindowServer flags.
- Use ordinary item anchors for concealed-section moves and left-of-item ordering.
- Keep numeric item ranks and optional trigger overrides separate from section ownership.
- Normalize image padding and reject empty captures to prevent self-triggered movement loops.
- Show Hammerspoon autosave names in the layout editor and item selectors.

## Build and updates

Build the `Thaw` scheme in Debug with Xcode, then sign with the same local development identity used for the installed build. Debug builds do not start Sparkle; upstream updates cannot silently replace these fixes. Rebase this branch onto a selected upstream release, resolve conflicts in the existing move/trigger extensions, then repeat the focused tests and live checks before replacing the app.

Focused tests: MenuBarItemOrderTests, MenuBarItemNameMemoryTests, MoveEndpointIdentityTests, MenuBarItemTriggersManagerPlanTests, MoveEventCoordinatesTests, MenuBarItemTriggerTests.

Live acceptance: hide/reveal an item, change and restore its rank, enable and remove a trigger rank override, confirm the dot stays left, restart, and observe no repeated moves after convergence. A refused physical move is latched until the order or trigger is edited; the pointer is restored on failures as well as successes.
