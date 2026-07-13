<script lang="ts">
	import { Heart } from '@lucide/svelte';

	let {
		count = 0,
		hearted = false,
		onclick
	}: {
		count: number;
		hearted: boolean;
		onclick: (e: MouseEvent) => void;
	} = $props();
</script>

<button
	{onclick}
	class="flex cursor-pointer items-center gap-1 rounded-full border-2 border-black p-2 transition-colors {hearted
		? 'border-red-500 bg-red-100'
		: 'hover:bg-gray-100'}"
	title={hearted ? 'Remove from wishlist' : 'Add to wishlist'}
>
	<Heart size={16} class={hearted ? 'fill-red-500 text-red-500' : ''} />
	<span class="text-xs font-bold">{count}</span>
</button>
