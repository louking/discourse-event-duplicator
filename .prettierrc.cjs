// Mirrors the relevant setting from @discourse/lint-configs/prettier without
// taking on that package (and prettier-plugin-ember-template-tag) as a
// dependency -- we have no .gjs/.gts files yet that would need it.
module.exports = {
  trailingComma: "es5",
};
