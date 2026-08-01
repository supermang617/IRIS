# GitHub Settings for Iris Releases

Verify these owner-controlled settings before any production signing or
semantic release publication.

## Actions

- General Actions permissions: allow GitHub Actions for this repository.
- Actions default token read-only: workflow permissions set the default
  `GITHUB_TOKEN` to read-only.
- Pull request workflows: disable automatic approval for PRs from forks.
- CI, GitHub default CodeQL setup, Dependency Review, and Dependabot require no
  custom secret. Keep no unnecessary secrets outside the protected production
  signing environment.
- Create an environment named `iris-production-release`, configure exactly one
  required reviewer (the repository owner as a user, with no additional users
  or teams), and limit deployment to protected branches. When that owner is the
  sole maintainer and also dispatches the workflow, **Prevent self-review must
  be off** or the release will deadlock with nobody able to approve signing. To
  enable self-review prevention, first use a distinct trusted reviewer and
  update the publisher's exact-reviewer policy to match that ownership model.
- Store `IRIS_SIGNING_PFX_BASE64`, `IRIS_SIGNING_PFX_PASSWORD`, and
  `IRIS_MSIX_PUBLISHER` as environment secrets, never repository secrets.
- Set the environment variable `IRIS_PRODUCTION_GATE_CONFIGURED=true` only
  inside `iris-production-release`, after the environment and `main`
  protections have been verified. Do not duplicate it at repository scope.
- `.github/workflows/release.yml` is owner-dispatched with an existing semantic
  tag. Pushing a tag alone cannot start production signing. The workflow
  requires the tag, checked-out source, and current `origin/main` head to be the
  same commit, and it creates a private draft only. Concurrent dispatches for
  the same tag are serialized.
- The protected signing job has `contents: read`, disables persisted checkout
  credentials, and is the only job that receives the PFX. A separate job with
  no signing secrets receives `contents: write` only to atomically create a
  new private draft. GitHub returns an error if the tag already has a release;
  the workflow never reuses or overwrites one.
- The signing job retains only the small immutable
  `iris-signed-provenance-<tag>-attempt-<run-attempt>` Actions artifact for ten
  days. It contains both the unsigned build/tool/lock provenance and the
  signed-asset provenance that binds its SHA-256. The two large job-to-job
  transfers use run-ID-and-attempt-bound Actions cache keys so a workflow re-run
  cannot collide with or silently replace an earlier payload. An always-running
  cleanup job has only `actions: write`, enumerates exact key/ref matches, and
  deletes only those two transient cache IDs after the draft job. The private
  draft and eventual public release include both provenance JSON files for
  auditability.
- If an attempt fails before it creates the private draft, choose **Re-run all
  jobs**, not **Re-run failed jobs**. A partial re-run deliberately cannot reuse
  an upstream transfer cache from an earlier run attempt. If draft creation
  succeeded but a later verification failed, inspect that exact unpublished
  draft and delete it before owner-dispatching a fresh full run; the workflow
  will never overwrite or reuse it.
- Public release publication is a separate owner-side command after clean-VM
  evidence exists. The disposable guest itself runs WACK against the exact
  signed MSIX and lifecycle schema 3 binds the package and WACK report hashes.
  The publisher requires that PASS report, the exact workflow run ID, and the
  owner-pinned signer subject/thumbprint, verifies recorded environment
  approval, downloads that run's immutable provenance, and binds every draft
  asset and external gate report before publication.

## Security

- Enable Dependabot alerts.
- Enable Dependabot security updates.
- Enable GitHub default CodeQL setup and code scanning alerts.
- Enable secret scanning alerts if the repository plan supports them.
- Keep dependency review on pull requests.
- Enable immutable releases and verify
  `GET /repos/supermang617/IRIS/immutable-releases` reports `enabled: true`
  before publication.

## Pages

- Verify GitHub Pages source is the intended repository source for the public
  Iris site.
- Keep the existing SHA-pinned `.github/workflows/pages.yml` deployment
  enabled, with validation read-only and Pages-write/OIDC permission restricted
  to its deploy job.
- Do not add cloud services, telemetry, webhooks, deploy keys, OAuth Apps,
  GitHub Apps, or marketplace scanners for the v1 release.
- Upload `site/assets/iris-social-preview.jpg` under Settings > General >
  Social preview, then verify GitHub's rendered Open Graph image. Committing
  the file alone does not configure the repository preview.

## Notifications

- Disable push email notifications if they are noisy for normal development.

## Branch Protection Recommendation

Required before setting `IRIS_PRODUCTION_GATE_CONFIGURED=true`:

- Require a pull request before merging.
- Require status checks to pass before merging.
- Required checks on `main`: `Validate`, `Analyze (actions)`,
  `Analyze (javascript-typescript)`, `Analyze (python)`, and `Analyze (rust)`.
  Each of these runs on the resulting `main` commit, so the final publisher can
  verify its latest result. Keep `Dependency Review / Dependency Review`
  enabled on pull requests, but do not add that PR-only context to the required
  `main`-head set unless its workflow is also changed to run on pushes to
  `main`.
- Require branches to be up to date before merging.
- Require conversation resolution before merging.
- Include administrators in the protection.
- Block force pushes.
- Block branch deletion.
- Require linear history only if the maintainer wants squash/rebase-only merges.
- Add an active tag ruleset targeting `refs/tags/v*.*.*`; the workflow performs
  the strict numeric semantic-version check. Give the ruleset no bypass
  actors, allow creation, and prevent matching-tag update and deletion. Both
  the signing workflow and final publisher verify this rule before proceeding.
