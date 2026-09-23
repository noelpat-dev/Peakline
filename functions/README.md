# Peakline backup functions

Run the Auth and Firestore emulators from the repository root before exercising
these functions. `deleteBackup` is dry-run unless the callable receives
`{ "confirm": true }`; it only removes the authenticated user's backup
descendants and is safe to retry when documents are already absent. Production
deployment and retention cleanup require a reviewed Firebase project and are
deliberately outside local validation.

The retention default protects the newest three generations and clamps callers
to five. The client keeps the latest pointer until a complete generation is
written; server cleanup must preserve that pointer and in-flight generations.
