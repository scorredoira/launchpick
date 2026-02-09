Commit, push, build release DMGs, and publish a new GitHub release. Do ALL of these steps without asking for confirmation:

1. Run `git status` and `git diff` to see all changes.
2. Stage all modified/new source files (not .build/, not release/). Create a concise commit message describing the changes. Do NOT include Co-Authored-By. Commit and push.
3. Determine the next version by checking `gh release list --limit 1` and incrementing the minor version (e.g. v1.5 -> v1.6).
4. Build both architectures:
   - `swift build -c release --arch arm64`
   - `swift build -c release --arch x86_64`
5. Create DMGs in the `release/` directory:
   - For each arch, create a temp app bundle, copy binary + Info.plist + AppIcon.icns, sign it, then:
   - `hdiutil create -volname "Launchpick" -srcfolder <temp> -ov -format UDZO release/Launchpick-<arch>.dmg`
6. Create the GitHub release: `gh release create <version> release/*.dmg --title "<version>" --notes "<summary of changes>"`
7. Report the release URL when done.
