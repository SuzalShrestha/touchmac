import js from "@eslint/js";
import oxlint from "eslint-plugin-oxlint";
import globals from "globals";

// oxlint runs first and fast; eslint adds what oxlint does not cover, and the oxlint
// plugin switches off the eslint rules oxlint already checks.
export default [
  { ignores: ["node_modules/", "app/.build/", "app/build/"] },
  js.configs.recommended,
  { files: ["docs/**/*.js"], languageOptions: { sourceType: "script", globals: globals.browser } },
  ...oxlint.buildFromOxlintConfigFile(".oxlintrc.json"),
];
