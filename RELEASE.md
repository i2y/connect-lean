# Releasing connect-lean

1. Make sure `main` passes CI, including the conformance suite.

2. On a new branch, prepare version X.Y.Z. Before 1.0, increase the minor
   version for new features or breaking changes, and the patch version for
   fixes only.

   - Set `version` in `lakefile.lean`, and `clientUserAgent` in
     `Connect/Client.lean`.
   - In `CHANGELOG.md`, turn "Unreleased" into "[X.Y.Z] - YYYY-MM-DD", add an
     empty "Unreleased" section above it, and update the links at the bottom.
   - Update the version in the installation example of `README.md`.

3. Open a pull request titled "Prepare for vX.Y.Z", and merge it once CI
   passes. Merge nothing else until the release is out.

4. Tag the merge commit and push the tag:

   ```console
   $ git tag vX.Y.Z
   $ git push origin vX.Y.Z
   ```

   Lake treats tags of the form `v` followed by a digit as versions, and so
   does [Reservoir](https://reservoir.lean-lang.org), which lists the package.

5. Create a GitHub release for the tag, titled "vX.Y.Z", with the changelog
   entry as its notes. Credit every contributor.
