<script lang="ts">
	import { Spool } from '@lucide/svelte';

	let { seed = 0 }: { seed?: number } = $props();

	function seededRandom(s: number) {
		return () => {
			s = Math.sin(s) * 10000;
			return s - Math.floor(s);
		};
	}

	let spools = $derived.by(() => {
		const random = seededRandom(seed);
		const count = Math.floor(random() * 4) + 5;
		const items = [];

		for (let i = 0; i < count; i++) {
			items.push({
				x: random() * 80 + 10,
				y: random() * 80 + 10,
				size: random() * 20 + 16,
				rotation: random() * 360,
				opacity: random() * 0.3 + 0.1
			});
		}

		return items;
	});
</script>

<div class="relative h-full w-full overflow-hidden bg-gray-50">
	{#each spools as spool, _i}
		<div
			class="absolute text-black"
			style="left: {spool.x}%; top: {spool.y}%; transform: translate(-50%, -50%) rotate({spool.rotation}deg); opacity: {spool.opacity};"
		>
			<Spool size={spool.size} strokeWidth={1.5} />
		</div>
	{/each}
</div>
