import prettier from 'eslint-config-prettier';
import path from 'node:path';
import { includeIgnoreFile } from '@eslint/compat';
import js from '@eslint/js';
import svelte from 'eslint-plugin-svelte';
import { defineConfig } from 'eslint/config';
import globals from 'globals';
import ts from 'typescript-eslint';
import svelteConfig from './svelte.config.js';

const gitignorePath = path.resolve(import.meta.dirname, '..', '.gitignore');

export default defineConfig(
	includeIgnoreFile(gitignorePath),
	js.configs.recommended,
	...ts.configs.recommended,
	...svelte.configs.recommended,
	prettier,
	...svelte.configs.prettier,
	{
		languageOptions: { globals: { ...globals.browser, ...globals.node } },
		rules: {
			// typescript-eslint strongly recommend that you do not use the no-undef lint rule on TypeScript projects.
			// see: https://typescript-eslint.io/troubleshooting/faqs/eslint/#i-get-errors-from-the-no-undef-rule-about-global-variables-not-being-defined-even-though-there-are-no-typescript-errors
			'no-undef': 'off',
			// Allow unused vars prefixed with _
			'@typescript-eslint/no-unused-vars': [
				'error',
				{
					argsIgnorePattern: '^_',
					varsIgnorePattern: '^_',
					caughtErrorsIgnorePattern: '^_'
				}
			],
			// Allow empty catch blocks
			'no-empty': ['error', { allowEmptyCatch: true }],
			// Allow expression statements (e.g. short-circuit evaluations)
			'@typescript-eslint/no-unused-expressions': 'off'
		}
	},
	{
		files: ['**/*.svelte', '**/*.svelte.ts', '**/*.svelte.js'],
		languageOptions: {
			parserOptions: {
				projectService: true,
				extraFileExtensions: ['.svelte'],
				parser: ts.parser,
				svelteConfig
			}
		},
		rules: {
			// Static SvelteKit apps use plain hrefs and goto() without resolve()
			'svelte/no-navigation-without-resolve': 'off',
			// {@html} is used intentionally for trusted markdown/HTML content
			'svelte/no-at-html-tags': 'off',
			// Each blocks don't always need keys (e.g. static lists)
			'svelte/require-each-key': 'off',
			// Allow built-in mutable classes in non-reactive contexts
			'svelte/prefer-svelte-reactivity': 'off',
			// Allow unused svelte-ignore comments (rules may be conditionally triggered)
			'svelte/no-unused-svelte-ignore': 'warn'
		}
	}
);
