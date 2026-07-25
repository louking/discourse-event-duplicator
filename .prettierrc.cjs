// Mirrors @discourse/lint-configs/prettier's relevant settings, without
// taking on that whole package as a dependency.
const templateTagPluginPath = require.resolve(
  "prettier-plugin-ember-template-tag"
);

module.exports = {
  plugins: [templateTagPluginPath],
  trailingComma: "es5",
  overrides: [
    {
      files: ["*.gjs", "*.gts"],
      options: {
        parser: "ember-template-tag",
        templateExportDefault: true,
      },
    },
  ],
};
