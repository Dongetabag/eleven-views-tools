# Privacy

Eleven Views Tools is local-first. Its core features run on your Mac, and the app does not require an Eleven Views account.

## The short version

- There is no automatic telemetry, advertising, or third-party tracking.
- Eleven Views does not sell personal information.
- Preferences, clipboard history, captures, and other saved state stay in the app's local storage unless you deliberately export or share them.
- Feedback opens a visible email draft to [dev@elevenviews.io](mailto:dev@elevenviews.io). Nothing is sent until you send that message from your mail app.
- Screenshot and recording link uploads are disabled until an Eleven Views-owned sharing service is provisioned and reviewed.

## Local data and permissions

System readings, window information, clipboard history, Shelf files, audio controls, and automation state are processed on your Mac through native macOS APIs. Copy Text from Screen uses Apple's on-device Vision framework. Recent capture caches remain local and are bounded by the app.

macOS permissions such as Accessibility, Screen Recording, Microphone, and Automation are used only for their visible features. Skipping a permission leaves that feature unavailable without disabling the rest of the app. See the [permissions guide](PERMISSIONS.md).

## Network connections

Eleven Views Tools makes network requests only for visible features:

1. **Updates.** When update checks are enabled, the app asks GitHub's public releases API for releases from `Dongetabag/eleven-views-tools`. Downloads come from that repository's GitHub releases.
2. **Internet speed test.** Starting a speed test contacts Cloudflare's public endpoints at `speed.cloudflare.com`.
3. **Homebrew.** Homebrew actions run the local `brew` command, which may contact Homebrew, GitHub, or package vendors. Popularity badges use public aggregate data from `formulae.brew.sh`.
4. **App updates.** Enabled Homebrew and App Store sources may contact Homebrew and Apple's public lookup service. The App Store source sends installed App Store bundle identifiers and the Mac's region so it can compare versions.
5. **Feedback.** Pressing Open email draft creates a local `mailto:` draft addressed to `dev@elevenviews.io`. The draft contains only the text you entered and, if selected, the app version, build, macOS version, Mac model, and app language shown in the form. Your mail provider processes a message only after you choose to send it.

Screenshot and recording link upload controls ship off and have no production endpoint. A future release will update this notice before enabling an Eleven Views-operated sharing service.

There are no hidden beacons or background uploads.

## Questions

Visit [elevenviews.io](https://elevenviews.io), email [dev@elevenviews.io](mailto:dev@elevenviews.io), or review [support](../SUPPORT.md).
