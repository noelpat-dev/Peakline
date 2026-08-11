# Engineering Decisions

This is a short record of the engineering choices I made while building Peakline. I keep the decisions concrete so the repository shows how the product works, not just what it looks like.

## Local-first data ownership

I chose SwiftData as the everyday source of truth because workout logging has to remain useful in a gym with unreliable connectivity. Firebase is an encrypted recovery copy, not a remote dependency for every navigation or keystroke. That boundary keeps the main interaction path fast and makes offline behavior explicit.

## Prepared snapshots at route boundaries

I introduced immutable value snapshots for Coach, Workout Preview, History, and startup-sensitive routes. Views receive the data needed for their first useful frame before navigation, then attach live observation after the transition. This makes the route easier to reason about and gives me measurable places to test responsiveness instead of relying on subjective smoothness.

## Deterministic, explainable coaching

I kept recommendations local and deterministic rather than making the product depend on an opaque AI service. Readiness signals are eligible only when their data is valid, missing evidence stays unavailable, and the UI explains which signals influenced a result. The trade-off is less artificial breadth, but the behaviour is testable and honest about uncertainty.

## Safe backup replacement

I use versioned backup envelopes, encrypted payloads, immutable cloud generations, and a pointer document as the commit point. Restore validates identifiers and relationships in an in-memory preflight before replacing local data. The cloud path now also bounds payload size, record count, and chunk count so malformed metadata cannot trigger unbounded work.

## Native platform behaviour first

I prefer SwiftUI navigation, system accessibility, Dynamic Type, native gestures, and semantic colour tokens before adding custom interaction machinery. Custom code is reserved for product-specific behaviour such as route-local workout reordering, target calculations, and performance instrumentation. This keeps the app familiar while preserving room for a distinct product identity.

## Measurement as part of the feature

I maintain unit, UI, and focused performance checks alongside the implementation. The current recorded run passed 131 unit tests and measured Today-to-Coach at 214 ms, Coach-to-Preview at 272 ms, and root-tab switching at 84 ms. These numbers are evidence from a run, not a promise that every device behaves identically.

## Compatibility during the Peakline rename

The visible product identity is Peakline, while the Xcode project, targets, source directory, and bundle identifier retain GymTracker compatibility names for the existing local install and Firebase configuration. I treat that as a deliberate migration boundary rather than mixing a branding rename with an unrelated data or module migration.
