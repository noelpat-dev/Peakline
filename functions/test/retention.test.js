const assert = require('assert');
const { retentionPlan } = require('../retention');

const generations = [
  { id: 'old', createdAt: 1 },
  { id: 'newest', createdAt: 3 },
  { id: 'middle', createdAt: 2 },
  { id: 'abandoned', createdAt: 0 }
];

assert.deepStrictEqual(retentionPlan(generations, 3), ['abandoned']);
assert.deepStrictEqual(retentionPlan(generations, 0), ['middle', 'old', 'abandoned']);
assert.deepStrictEqual(retentionPlan(generations, 99), []);
console.log('retention tests passed');
