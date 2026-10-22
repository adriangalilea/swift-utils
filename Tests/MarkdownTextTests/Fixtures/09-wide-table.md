A table wider than the column scrolls; a long cell wraps at its own measure:

| Step | Who | Why | Command | Status | Took |
|:-----|:---:|:----|:--------|:------:|-----:|
| Install Xcode on the build Mac, plus the iOS and tvOS platforms | **you**, once | Needs your Apple ID and `sudo` (licence, `xcode-select`). Screen Sharing or the App Store, then the platform downloads. | `xcodebuild -downloadPlatform iOS` | done | 41 min |
| Install mise via Homebrew, and download and verify the runner | me | No `sudo`, no keys. | `brew install mise` | done | 2 min |
| Register the runner | **you** | The step the safety check blocks for me, and rightly so. | `./config.sh --unattended` | open | |
| CI: pushes to `main` on the Mac, pull requests on GitHub | me | | | open | |
