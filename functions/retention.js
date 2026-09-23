const DEFAULT_RETENTION = 3;
const MAX_RETENTION = 5;

function retentionPlan(generations, limit = DEFAULT_RETENTION) {
  const boundedLimit = Math.max(1, Math.min(MAX_RETENTION, limit));
  const ordered = [...generations].sort((a, b) => {
    const left = Number(a.createdAt || 0);
    const right = Number(b.createdAt || 0);
    return right - left;
  });
  const protectedIds = new Set(ordered.slice(0, boundedLimit).map(item => item.id));
  return ordered.filter(item => !protectedIds.has(item.id)).map(item => item.id);
}

module.exports = { DEFAULT_RETENTION, MAX_RETENTION, retentionPlan };
