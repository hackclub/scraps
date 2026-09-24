<script lang="ts">
	// Replaces the old "click a button, wait, see a number" try-luck flow with a
	// CS:GO-style case-opening strip (inspired by the caseStrip in the scrapcalc
	// side project) that spins a long run of 1-100 tiles and settles precisely on
	// the roll the backend already returned, so nothing here decides the outcome
	// — it only dramatizes a result that's already final.
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';

	let {
		itemName,
		finalNumber,
		winThreshold,
		won,
		onDone
	}: {
		itemName: string;
		finalNumber: number;
		// The real cutoff a roll must land at-or-under to win — pass
		// computeRollThreshold(effectiveProbability) from $lib/utils, not the
		// raw displayed probability. They differ on purpose (see
		// shop_controller.rb's try_luck comment on display_rolled), and tiles
		// 1..winThreshold are the tiles that actually win.
		winThreshold: number;
		won: boolean;
		onDone: () => void;
	} = $props();

	const TILE_W = 76;
	const GAP = 12;
	const STEP = TILE_W + GAP;
	const PAD = 12;
	const CYCLES = 7;
	const LANDING_CYCLE = 5;

	const tiles = Array.from({ length: CYCLES * 100 }, (_, i) => (i % 100) + 1);
	const clampedFinal = Math.min(100, Math.max(1, Math.round(finalNumber)));
	const targetIndex = LANDING_CYCLE * 100 + (clampedFinal - 1);

	let windowEl: HTMLDivElement;
	let translateX = $state(0);
	let phase = $state<'ready' | 'spinning' | 'settled'>('ready');

	function easeOutCubic(t: number) {
		return 1 - Math.pow(1 - t, 3);
	}

	onMount(() => {
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

		const pointerX = (windowEl?.clientWidth ?? 460) / 2;
		const tileCenterX = targetIndex * STEP + TILE_W / 2 + PAD;
		const target = pointerX - tileCenterX;

		const revUp = reduce ? 0 : 150;
		const duration = reduce ? 30 : 2200 + Math.random() * 500;
		const settleHold = reduce ? 30 : 900;

		const revTimer = setTimeout(() => {
			phase = 'spinning';
			const start = performance.now();
			let raf = 0;
			function frame(now: number) {
				const t = Math.min(1, (now - start) / duration);
				translateX = target * easeOutCubic(t);
				if (t < 1) {
					raf = requestAnimationFrame(frame);
				} else {
					translateX = target;
					phase = 'settled';
					setTimeout(onDone, settleHold);
				}
			}
			raf = requestAnimationFrame(frame);
			return () => cancelAnimationFrame(raf);
		}, revUp);

		return () => clearTimeout(revTimer);
	});
</script>

<div
	class="fixed inset-0 z-60 flex flex-col items-center justify-center bg-black/70 px-6"
	transition:fade={{ duration: 150 }}
>
	<p class="mb-1 text-sm font-bold text-white/60">rolling for</p>
	<p class="mb-6 max-w-full truncate text-2xl font-bold text-white">{itemName}</p>

	<div
		bind:this={windowEl}
		class="relative h-20 w-full max-w-[460px] overflow-hidden rounded-2xl border-4 border-black bg-white"
	>
		<div class="pointer-events-none absolute inset-y-0 left-1/2 z-10 w-0 -translate-x-1/2">
			<div
				class="absolute top-0 left-1/2 h-0 w-0 -translate-x-1/2 border-x-[9px] border-t-[11px] border-x-transparent border-t-black"
			></div>
			<div
				class="absolute bottom-0 left-1/2 h-0 w-0 -translate-x-1/2 border-x-[9px] border-b-[11px] border-x-transparent border-b-black"
			></div>
		</div>

		<div
			class="flex h-full items-center gap-[12px] px-[12px]"
			style="transform: translateX({translateX}px)"
		>
			{#each tiles as n, i (i)}
				{@const isLanded = phase === 'settled' && i === targetIndex}
				<div
					class="flex h-[58px] w-[76px] shrink-0 items-center justify-center rounded-xl border-2 border-black text-lg font-bold transition-colors duration-200 {isLanded
						? won
							? 'bg-green-600 text-white'
							: 'bg-red-600 text-white'
						: n <= winThreshold
							? 'bg-green-100'
							: 'bg-white'}"
				>
					{n}
				</div>
			{/each}
		</div>
	</div>

	<p class="mt-6 text-lg font-bold text-white">
		{#if phase === 'settled'}
			{won ? 'you won!' : 'so close!'}
		{:else}
			rolling…
		{/if}
	</p>
</div>
