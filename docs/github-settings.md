# GitHub Settings for Iris v0.1.2

Verify these manually before publishing the public `v0.1.2` release.

## Actions

- General Actions permissions: allow GitHub Actions for this repository.
- Actions default token read-only: workflow permissions set the default
  `GITHUB_TOKEN` to read-only.
- Pull request workflows: disable automatic approval for PRs from forks.
- Secrets and variables: no unnecessary secrets or variables are required for
  CI, GitHub default CodeQL setup, Dependency Review, Dependabot, or release
  packaging.
- Release workflow exception: `.github/workflows/release.yml` explicitly
  requests `contents: write` so it can attach release assets on version tags.

## Security

- Enable Dependabot alerts.
- Enable Dependabot security updates.
- Enable GitHub default CodeQL setup and code scanning alerts.
- Enable secret scanning alerts if the repository plan supports them.
- Keep dependency review on pull requests.

## Pages

- Verify GitHub Pages source is the intended repository source for the public
  Iris site.
- Do not enable a Pages deployment workflow unless the site source changes to
  require it.
- Do not add cloud services, telemetry, webhooks, deploy keys, OAuth Apps,
  GitHub Apps, or marketplace scanners for the v0.1.2 release.

## Notifications

- Disable push email notifications if they are noisy for normal development.

## Branch Protection Recommendation

Do not enable branch protection until CI has passed on `main`.

Recommended settings after CI is green:

- Require a pull request before merging.
- Require status checks to pass before merging.
- Required checks: `CI / Validate`, GitHub default CodeQL setup checks, and
  `Dependency Review / Dependency Review` once branch protection is enabled for
  pull requests.
- Require branches to be up to date before merging.
- Require conversation resolution before merging.
- Block force pushes.
- Block branch deletion.
- Require linear history only if the maintainer wants squash/rebase-only merges.
