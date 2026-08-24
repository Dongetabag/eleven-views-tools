#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Cleanly removes Eleven Views Tools and every piece of system state it created:
# the login item, TCC permissions, preferences, saved state and (if present)
# the password-free closed-lid sudoers rule. Leaves no dead entries behind.
set -uo pipefail

BUNDLE="io.elevenviews.tools"
DEV_BUNDLE="io.elevenviews.tools.dev"
APP="/Applications/Eleven Views Tools.app"
DEV_APP="/Applications/Eleven Views Tools (Developer).app"

echo "▸ Quitting…"
pkill -x ElevenViewsTools 2>/dev/null || true
pkill -x ElevenViewsToolsDeveloper 2>/dev/null || true
sleep 0.5

# Detach from the system from inside whichever bundle still exists: unregisters
# the login item (no BTM tombstone) and restores normal sleep.
for candidate in "$APP/Contents/MacOS/ElevenViewsTools" "$DEV_APP/Contents/MacOS/ElevenViewsToolsDeveloper"; do
    if [[ -x "$candidate" ]]; then
        echo "▸ Detaching login item and restoring sleep…"
        "$candidate" --uninstall || true
        break
    fi
done

echo "▸ Resetting permissions (Accessibility, Screen Recording)…"
tccutil reset All "$BUNDLE" >/dev/null 2>&1 || true
tccutil reset All "$DEV_BUNDLE" >/dev/null 2>&1 || true

echo "▸ Removing app, preferences and saved state…"
rm -rf "$APP" "$DEV_APP"
defaults delete "$BUNDLE" >/dev/null 2>&1 || true
defaults delete "$DEV_BUNDLE" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE.plist"
rm -f "$HOME/Library/Preferences/$DEV_BUNDLE.plist"
rm -rf "$HOME/Library/Saved Application State/$BUNDLE.savedState"
rm -rf "$HOME/Library/Saved Application State/$DEV_BUNDLE.savedState"

RULE="/etc/sudoers.d/eleven-views-tools-clamshell"
if [[ -e "$RULE" ]]; then
    echo "▸ Removing closed-lid sudoers rule (asks for your admin password)…"
    osascript -e "do shell script \"rm -f '$RULE'\" with administrator privileges with prompt \"Eleven Views Tools uninstaller\"" || true
fi

echo "✓ Eleven Views Tools fully removed."
