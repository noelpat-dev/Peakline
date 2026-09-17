# Known Issues

This file records current constraints and regression boundaries. Dated build, test, and timing results live in the [verification record](verification-2026-09-17.md).

## Physical-device acceptance

- Simulator validation does not establish haptic quality, high-refresh-rate smoothness, camera capture, live HealthKit access, or Firebase reinstall recovery.
- The final physical-device pass should cover Light and Dark appearance, maximum practical Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, cramped Logger/overlay layouts, Preview drag, and genuine-PR completion.
- A free-development signing profile can expire quickly. Device installation also requires an unlocked, trusted device and a valid signing identity.

## Persistence and migration

- There is no formal SwiftData migration plan for future schema changes. New stored fields need compatible defaults, fixtures, migration coverage, and rollback validation before release.
- Live SwiftData models, queries, and contexts must not cross a suspending or detached task boundary. Build immutable value snapshots on the owning actor first.
- Historical workout rendering must tolerate changed or missing exercise, split, template, and UUID references.

## Firebase backup and HealthKit

- A real `GoogleService-Info.plist` is intentionally not committed. Without it, Peakline runs locally but cannot protect local data from app deletion through account backup.
- Firebase Email/Password Authentication and Cloud Firestore must be enabled with per-user rules. A forgotten encryption passphrase makes a remote backup unrecoverable, and service quotas can pause backup.
- Full sign-in, backup, uninstall/reinstall, and restore validation requires a physical device and a test account.
- HealthKit remains optional. Permission may be unavailable, denied, or revoked, and imported nutrition or sleep data still requires an explicit local review boundary.

## Exercise Guide fidelity

- Some catalogue entries intentionally share representative pose artwork. Artwork metadata must never overwrite an exercise's real name, equipment, or muscle data.
- The three-pose illustrations are orientation aids, not medically validated technique instructions.

## Nutrition imports

- Barcode, Open Food Facts, OCR, parser, and comparison results remain editable suggestions until the user explicitly saves them.
- Saved/imported-food navigation uses stable identifiers; live SwiftData objects must not be retained across route or asynchronous boundaries.
- Open Food Facts access is read-only from Peakline's side.

## Coaching certainty

- Readiness and coaching are deterministic but necessarily incomplete. Missing signals remain unknown rather than becoming a neutral or poor score.
- Sparse readiness stays provisional and cannot independently prescribe aggressive training, recovery, or deload urgency.
- Sleep must represent a real overnight session ending on the evaluated day; future activity, stale nutrition, and insufficient personal baselines remain ineligible.

## Performance-sensitive boundaries

- Preserve the enforced 300 ms warm/root and 500 ms deep-route budgets, 50 ms interactive notification refresh limit, Preview warm-cache requirement, duplicate-navigation checks, and warning scans in `Scripts/verify_performance_acceptance.sh`.
- Route timing is currently unclosed: the latest [verification record](verification-2026-09-17.md) carries focused replacement checks, and a full verifier plus five-sample matrix must be rerun before performance acceptance is claimed. Retained samples vary (Preview 493 ms in one run, 550 ms in a later clean run; `workout.coach` 81 ms then 992 ms), so do not treat a single fast sample as proof.
- History must retain its displayed snapshot while scrolling and decelerating, then coalesce pending source changes after a genuinely idle interval.
- Preview must keep one pinned prepared generation while mounted. Do not publish source/catalog/cache changes into the live route or duplicate the detailed exercise order.
- Active Preview capacity is deliberately bounded. Reprofile first-frame time and memory before expanding startup preparation.
- Exercise trend charts need at least two completed sessions for a meaningful line. Empty and one-session states must remain explicit.
- Simulator timings vary with thermal and service load. Use isolated comparable samples and report every sample rather than weakening a threshold.

## Product scope

- Peakline currently emphasises best-set volume instead of total tonnage.
- Multi-device conflict handling, Apple Watch support, broader HealthKit ingestion, and advanced periodisation remain future work rather than partially supported claims.
