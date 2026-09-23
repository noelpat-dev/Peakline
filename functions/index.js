const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { retentionPlan, DEFAULT_RETENTION } = require('./retention');

initializeApp();

// Trusted cleanup is intentionally dry-run by default. Production deletion
// requires an explicit confirm flag and is idempotent for missing descendants.
exports.deleteBackup = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const db = getFirestore();
  const root = db.collection('users').doc(request.auth.uid).collection('backups');
  const docs = await root.get();
  const result = { dryRun: request.data?.confirm !== true, deleted: 0 };
  for (const backup of docs.docs) {
    const generations = await backup.ref.collection('generations').get();
    for (const generation of generations.docs) {
      const chunks = await generation.ref.collection('chunks').get();
      if (result.dryRun) {
        result.deleted += chunks.size + 1;
      } else {
        const batch = db.batch();
        chunks.docs.forEach(chunk => batch.delete(chunk.ref));
        batch.delete(generation.ref);
        await batch.commit();
        result.deleted += chunks.size + 1;
      }
    }
    const legacyChunks = await backup.ref.collection('chunks').get();
    if (result.dryRun) {
      result.deleted += legacyChunks.size + 1;
    } else {
      const batch = db.batch();
      legacyChunks.docs.forEach(chunk => batch.delete(chunk.ref));
      batch.delete(backup.ref);
      await batch.commit();
      result.deleted += legacyChunks.size + 1;
    }
  }
  return result;
});

exports.retentionDefaults = { generations: DEFAULT_RETENTION };
