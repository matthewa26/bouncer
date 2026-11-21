# Xcode and Swift Packages

Run Bouncer as part of every build, with its findings shown inline next to the compiler's.

## Overview

There are two ways to put Bouncer in a build:

- **A Run Script phase** in an Xcode project, added by `bouncer xcode install`. It uses the `bouncer`
  you installed, and needs nothing added to the project's dependencies.
- **The SwiftPM plugin** from [bouncer-plugin](https://github.com/matthewa26/bouncer-plugin), for Swift
  packages built with `swift build` (it works in Xcode too). It brings in a prebuilt Bouncer, so nothing
  needs to be installed first, and Bouncer's own dependencies stay out of your package graph.

Both print findings in the compiler's diagnostic format (`--format xcode`), so Xcode shows them in the
editor and the Issue navigator, attached to their file and line.

## The Run Script phase

```sh
cd MyApp
bouncer xcode install                       # asks which targets
bouncer xcode install --target MyApp        # or name them
bouncer xcode install --scope check         # only staged files, for large repositories
bouncer xcode install --fail-on never       # report everything as warnings
bouncer xcode uninstall
```

`install` finds the one `.xcodeproj` in the current directory (or takes `--project`), adds a **Bouncer**
phase before Compile Sources in each chosen target, and backs up `project.pbxproj` to
`project.pbxproj.bouncer-backup` the first time. Running it again updates the phase rather than adding a
second one.

The phase looks for `bouncer` in Homebrew's and the installer's locations. If it isn't installed, the build
shows a warning and carries on.

- `--scope review`, the default, checks everything under the project folder on each build, so the findings
  match `bouncer review`. On a very large repository, `--scope check` checks only staged files instead.
- `--fail-on error`, the default, fails the build on error-severity findings, the same as a pre-commit
  hook. `warning` also fails on warnings; `never` shows every finding as a warning.

### Script sandboxing

Xcode 15 and later can sandbox Run Script phases (`ENABLE_USER_SCRIPT_SANDBOXING`). A sandboxed script can
read only the files listed as its inputs, one by one; a folder doesn't grant access to what's inside it. Bouncer
reads the whole source tree and runs `git`, so it can't work sandboxed. When a chosen target has sandboxing on,
`install` explains this and asks before turning it off for that target only;
`--disable-script-sandboxing` answers yes without asking. If it stays on, the phase warns on every build
rather than silently checking nothing.

## The SwiftPM plugin

Add the package, then the plugin to each target you want checked:

```swift
dependencies: [
    .package(url: "https://github.com/matthewa26/bouncer-plugin", from: "1.3.0"),
],
targets: [
    .target(name: "MyLibrary", plugins: [.plugin(name: "BouncerBuildPlugin", package: "bouncer-plugin")]),
]
```

The build plugin checks a target's sources whenever they change. `swift package bouncer` runs a full
`bouncer review` on demand. See the plugin's README for Xcode setup and its sandbox limits.
