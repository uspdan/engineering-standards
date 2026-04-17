/**
 * Conventional Commits — enforced on every PR via the commitlint CI job.
 * Types are the same set we document in CLAUDE.md §10.1.
 */
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'refactor', 'test', 'docs', 'chore', 'security'],
    ],
    // Keep titles readable; the description goes in the body.
    'header-max-length': [2, 'always', 100],
    // Subject should be lowercase-first (aligns with our existing commits).
    'subject-case': [2, 'never', ['upper-case', 'pascal-case', 'start-case']],
  },
};
