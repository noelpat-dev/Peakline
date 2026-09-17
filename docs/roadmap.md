# Roadmap

Peakline's north star is a local-first lifting coach that makes the full training loop clear: decide, preview, log, and review. The app already supports that loop; the roadmap prioritises reliability and depth over adding another broad feature layer.

## Now

- Keep the core Today, Coach, Preview, Logger, Summary, and History journey responsive under realistic accumulated data.
- Finish physical-device accessibility and interaction checks for Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, haptics, and high-refresh-rate displays.
- Validate encrypted Firebase backup and restore end to end without weakening SwiftData's local source-of-truth ownership.
- Protect nutrition import review, HealthKit consent boundaries, and failure recovery with focused regression coverage.

## Next

- Make nutrition reuse faster with copied meals/days, reusable meals and recipes, and goal-adherence trends.
- Deepen training analysis with total tonnage, PR lists, split consistency, and weekly volume summaries where they improve decisions.
- Strengthen migration fixtures and rollback coverage before any SwiftData schema evolution.
- Continue filling exact Exercise Guide artwork mappings only where licensed source assets already exist.

## Later

- Add deliberate attendance check-ins without creating empty workout sessions.
- Explore Apple Watch and broader HealthKit support after the phone experience and data-recovery path are proven.
- Consider multi-device sync and conflict handling after encrypted restore is reliable.
- Explore optional natural-language coaching and periodisation without replacing deterministic, explainable recommendations.

Completed behaviour belongs in the [README](../README.md) and [architecture guide](architecture.md). Current limitations belong in [known issues](known-issues.md), and measured acceptance belongs in the latest [verification record](verification-2026-09-17.md).
