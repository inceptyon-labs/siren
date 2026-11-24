# Upstream sync

Siren takes fixes from the `upstream` git remote by cherry-picking. Upstream
force-pushes `main`, so never merge it.

**Last synced:** `1603bd1` "Adjust ebook reader audio player" (2026-11-22), the
commit Siren forked from.

## Steps

1. `git fetch upstream`
2. List upstream commits since the last sync. Siren's public history starts at
   its own first commit and shares none with upstream, so go by the last synced
   commit:

   ```sh
   git log --oneline --reverse <last-synced>..upstream/main
   ```

   If upstream force-pushed and `<last-synced>` is gone from `upstream/main`,
   find the matching commit by message and compare the ranges:
   `git range-diff <last-synced>..<old-upstream-head> <new-match>..upstream/main`.
3. Cherry-pick the ones to take, oldest first: `git cherry-pick -x <sha>...`
4. Siren renamed upstream's project, folders, files, targets and types to Siren
   (2026-11-24). Git's rename detection carries most picks onto the new paths;
   where a pick brings back upstream's name in a path, type, string or
   identifier, rename it to Siren's before committing. Keep Siren's identifiers
   (`com.inceptyon.siren`, `group.com.inceptyon.siren`, `siren://`).
5. Build, then update **Last synced** above to the newest upstream commit taken.

## Skip

- Tip jar and RevenueCat changes (removed in Siren).
- Upstream's icons, alternate icons and widget glyph.
- README, PRIVACY, CHANGELOG, CONTRIBUTING and CODE-OF-CONDUCT changes.
