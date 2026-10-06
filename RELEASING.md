# Releasing

## One-time setup: Trusted Publishing

`release.yml` publishes the `id-calendar-tui-clariant` gem without an API key via
RubyGems **Trusted Publishing**. The gem does not exist yet, so register a
*pending* trusted publisher; the first release then creates the gem:

1. Sign in at https://rubygems.org and open **Settings → Trusted Publishers**
   (https://rubygems.org/profile/oidc/pending_trusted_publishers)
2. Click **Create** and configure:
   - **Gem name:** `id-calendar-tui-clariant`
   - **Repository owner:** `clariantb`
   - **Repository name:** `id-calendar-tui`
   - **Workflow filename:** `release.yml`
   - **Environment:** (leave blank)

The publisher must be `release.yml`. The holiday workflow deliberately dispatches
`release.yml` instead of calling it as a reusable workflow, because a reusable
workflow's OIDC token carries the caller's workflow and would not match.

## Holiday data releases (automatic)

`.github/workflows/update-holidays.yml` runs weekly. Whenever `data/holidays.json`
differs from the latest `v*` tag, it runs `scripts/bump_version.rb` (patch bump +
CHANGELOG entry), commits, tags `vX.Y.Z`, and runs
`gh workflow run release.yml --ref vX.Y.Z`. Nothing to do by hand.

## Code releases

```bash
# Update version in id-calendar-tui.gemspec
# Update CHANGELOG.md
git add .
git commit -m "Bump version to x.x.x"
git tag vx.x.x
git push origin vx.x.x
```

`release.yml` refuses to publish unless the tag equals `v` + the gemspec version
and `data/holidays.json` loads. It publishes to RubyGems and to GHCR
(`ghcr.io/clariantb/id-calendar-tui`).
