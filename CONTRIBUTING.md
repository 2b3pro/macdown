# Contributing to MacDown (2b3pro fork)

Thanks for helping keep MacDown alive on current macOS. This document covers how this fork works day to day. The original author's style guide has been folded in where it still serves the code; his personal preferences have been dropped.

## Scope of this fork

Contributions are welcome in these areas:

* Keeping the app building and running natively on current Xcode and macOS (no Rosetta, no deprecated-API crashes).
* The Quick Look extension (`MacDownQuickLook`).
* Printing and PDF export (margins, headers and footers, the PDF preferences pane).
* Bug fixes anywhere in the app.

If a change is not fork-specific and would help everyone, consider also offering it to [MacDownApp/macdown](https://github.com/MacDownApp/macdown). Upstream activity has been low since 2020, so do not block on it.

## Getting set up

Follow the **Development** section of the [README](README.md): Xcode 15 or later with the macOS 13 SDK, CocoaPods 1.16 or later, then `pod install` and open `MacDown.xcworkspace`.

Before opening a pull request, make sure that:

1. The **MacDown** scheme builds in both Debug and Release with no new warnings in code you touched.
2. The unit tests pass (`Product > Test`, or `xcodebuild -workspace MacDown.xcworkspace -scheme MacDown test`).
3. If you touched rendering, preferences, or the extension, the Quick Look preview still works: build, run the app once, select a `.md` file in Finder and press Space. `qlmanage` is not a reliable way to test data-based Quick Look extensions; use Finder.
4. If you changed the Podfile, commit the updated `Podfile.lock` too. The `Pods/` directory is not tracked.

## Coding style (Objective-C)

The codebase follows the upstream conventions below. Match the surrounding code when in doubt.

* **80 columns.** Long URLs in comments may exceed the limit; prefer the shortest permanent form of the URL.
* **Allman braces**: opening braces on their own line. Omit braces around a single-statement body, except inside an `if` / `else if` / `else` chain where all branches must match.
* **Implicit boolean checks** where the meaning is emptiness or nil-ness (`if (str.length)`, `if (obj)`). Use an explicit `== 0` / `!= 0` when comparing a real number such as an `NSRange` location or a coordinate.
* **Multi-line conditions** put the logical operator at the start of the continuation line, and add extra indentation when alignment would otherwise be ambiguous:

    ```c
    if (this_is_very_long
            || this_is_also_very_long)
        foo++;
    ```

* **Four spaces**, no tabs. No trailing whitespace. Files end with a newline. Xcode's "Automatically trim trailing whitespace" setting handles most of this.
* **Class prefix** is `MP`. New source files go in the matching group under `MacDown/Code/` (Application, Document, Extension, Preferences, Utility, View) or under `MacDownQuickLook/` for the extension.

## Quick Look extension notes

* The extension is sandboxed and cannot link the app's CocoaPods. It compiles Hoedown and `hoedown_html_patch.c` directly and mirrors the relevant parts of `MPRenderer`. If you change the app's rendering pipeline or add a rendering preference, make the matching change in `MPQuickLookPreviewProvider.m` so previews stay consistent.
* Preferences are read from the `com.uranusjr.macdown` defaults domain through a `shared-preference.read-only` entitlement. New keys need no entitlement change; new file locations do.
* Quick Look does not run JavaScript, so anything that depends on Prism, MathJax, or Mermaid is out of scope for the preview.

## Version control

### Branches and commits

* Work on a branch off `master` and rebase before opening the pull request. Merges of `.xib` and `project.pbxproj` files are painful; keep those changes in their own small commits so they can be reapplied if the rebase breaks.
* Commit subject lines: imperative mood, 72 characters or fewer, no trailing period. Use the body to explain **why**, not just what. Wrap the body at 72 columns.
* One logical change per commit. Formatting-only changes go in a separate commit from behavior changes.

### Pull requests

* Describe what changed, why, and how you verified it (the checklist above). Screenshots are welcome for UI and Quick Look changes.
* Small, focused PRs get reviewed and merged faster than large ones.
* The maintainer may squash or rebase your commits when merging. Authorship is preserved.

### Project file

Edit `MacDown.xcodeproj/project.pbxproj` through Xcode where possible. If you must edit it by hand, keep the diff minimal and confirm the project still opens and builds. Do not commit `xcuserdata`.

## Versioning and releases

The version comes from `Tools/version.txt` plus git tags; see **Versioning** in the README. Do not edit `CFBundleShortVersionString` or `CFBundleVersion` in the Info.plist files by hand; the "Update Build Number" build phase stamps both the app and the extension.

## Localization

Existing localizations come from upstream's Transifex project. New user-facing strings added in this fork should be added to the Base localization in English. Do not hand-edit the other `.lproj` folders unless you are a fluent speaker of that language.

## License

MacDown is MIT licensed (see [LICENSE.txt](LICENSE.txt)). By contributing, you agree that your contributions are licensed under the same terms.
