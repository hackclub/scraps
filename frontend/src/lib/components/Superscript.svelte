<script lang="ts">
	let { number, tooltip }: { number: number | string; tooltip: string } = $props();
</script>

<span class="group relative">
	<sup class="cursor-help hover:underline">{number}</sup>
	<span
		class="invisible absolute bottom-full left-1/2 z-10 mb-2 -translate-x-1/2 rounded border-2 border-dashed border-black bg-white px-3 py-2 text-sm whitespace-nowrap group-hover:visible"
	>
		{tooltip}
	</span>
</span>
