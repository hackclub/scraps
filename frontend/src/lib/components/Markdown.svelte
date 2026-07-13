<script lang="ts">
	import { Marked } from 'marked';

	interface Props {
		content: string;
		class?: string;
	}

	let { content, class: className = '' }: Props = $props();

	const marked = new Marked({
		breaks: true,
		gfm: true
	});

	const renderer = {
		link({ text }: { href: string; text: string }) {
			return text;
		},
		image() {
			return '';
		},
		html() {
			return '';
		},
		checkbox() {
			return '';
		}
	};

	marked.use({ renderer });

	function render(text: string): string {
		const result = marked.parse(text);
		if (typeof result !== 'string') return text;
		return result;
	}
</script>

<div class="markdown {className}">
	{@html render(content)}
</div>

<style>
	.markdown :global(h1) {
		font-size: 1.75rem;
		font-weight: 700;
		margin-bottom: 0.5rem;
	}
	.markdown :global(h2) {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: 0.5rem;
	}
	.markdown :global(h3) {
		font-size: 1.25rem;
		font-weight: 700;
		margin-bottom: 0.5rem;
	}
	.markdown :global(h4) {
		font-size: 1.125rem;
		font-weight: 700;
		margin-bottom: 0.25rem;
	}
	.markdown :global(h5),
	.markdown :global(h6) {
		font-size: 1rem;
		font-weight: 700;
		margin-bottom: 0.25rem;
	}
	.markdown :global(p) {
		margin-bottom: 0.5rem;
	}
	.markdown :global(p:last-child) {
		margin-bottom: 0;
	}
	.markdown :global(strong) {
		font-weight: 700;
	}
	.markdown :global(em) {
		font-style: italic;
	}
	.markdown :global(del) {
		text-decoration: line-through;
	}
	.markdown :global(code) {
		font-family: monospace;
		background-color: #f3f4f6;
		padding: 0.125rem 0.25rem;
		border-radius: 0.25rem;
		font-size: 0.875em;
	}
	.markdown :global(pre) {
		background-color: #f3f4f6;
		padding: 0.75rem;
		border-radius: 0.5rem;
		overflow-x: auto;
		margin-bottom: 0.5rem;
	}
	.markdown :global(pre code) {
		background: none;
		padding: 0;
	}
	.markdown :global(blockquote) {
		border-left: 3px solid #d1d5db;
		padding-left: 0.75rem;
		color: #6b7280;
		margin-bottom: 0.5rem;
	}
	.markdown :global(ul) {
		list-style-type: disc;
		padding-left: 1.5rem;
		margin-bottom: 0.5rem;
	}
	.markdown :global(ol) {
		list-style-type: decimal;
		padding-left: 1.5rem;
		margin-bottom: 0.5rem;
	}
	.markdown :global(li) {
		margin-bottom: 0.125rem;
	}
	.markdown :global(hr) {
		border: none;
		border-top: 1px solid #d1d5db;
		margin: 0.75rem 0;
	}
	.markdown :global(a) {
		color: inherit;
		text-decoration: none;
		pointer-events: none;
	}
	.markdown :global(img) {
		display: none;
	}
	.markdown :global(table) {
		display: none;
	}
</style>
