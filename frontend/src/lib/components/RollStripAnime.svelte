<script lang="ts">
	// Comparison twin of RollStrip.svelte: identical tiles/layout/math, but the
	// spin is driven by anime.js's animate() instead of a hand-rolled
	// requestAnimationFrame loop + manual easeOutCubic. Not wired into any real
	// flow — exists so the two can be judged side by side. If one wins, port
	// its approach into RollStrip.svelte and delete this file; don't keep both
	// live long-term.
	import { onMount, onDestroy } from 'svelte';
	import { fade } from 'svelte/transition';
	import { animate, type JSAnimation } from 'animejs';

	let {
		itemName,
		finalNumber,
		winThreshold,
		won,
		onDone
	}: {
		itemName: string;
		finalNumber: number;
		winThreshold: number;
		won: boolean;
		onDone: () => void;
	} = $props();

	const TILE_W = 60;
	const GAP = 10;
	const STEP = TILE_W + GAP;
	const PAD = 10;
	const CYCLES = 7;
	const LANDING_CYCLE = 5;

	const tiles = Array.from({ length: CYCLES * 100 }, (_, i) => (i % 100) + 1);
	const clampedFinal = Math.min(100, Math.max(1, Math.round(finalNumber)));
	const targetIndex = LANDING_CYCLE * 100 + (clampedFinal - 1);

	let windowEl: HTMLDivElement;
	let translateX = $state(0);
	let phase = $state<'ready' | 'spinning' | 'settled'>('ready');
	let anim: JSAnimation | null = null;

	onMount(() => {
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

		const pointerX = (windowEl?.clientWidth ?? 350) / 2;
		const tileCenterX = targetIndex * STEP + TILE_W / 2 + PAD;
		const target = pointerX - tileCenterX;

		const revUp = reduce ? 0 : 150;
		const duration = reduce ? 30 : 2200 + Math.random() * 500;
		const settleHold = reduce ? 30 : 900;

		// Animate a plain object's `x` — anime.js mutates it in place every
		// tick, onUpdate just copies that into the $state var the template
		// reads. `ease: 'outCubic'` matches RollStrip's hand-rolled cubic for a
		// fair comparison; swap for 'outExpo' or a spring (e.g. `outElastic(1,
		// .6)`) to see anime.js do something the manual version can't easily.
		const rollState = { x: 0 };
		anim = animate(rollState, {
			x: target,
			duration,
			delay: revUp,
			ease: 'outCubic',
			onBegin: () => {
				phase = 'spinning';
			},
			onUpdate: () => {
				translateX = rollState.x;
			},
			onComplete: () => {
				phase = 'settled';
				setTimeout(onDone, settleHold);
			}
		});
	});

	onDestroy(() => {
		anim?.pause();
	});
</script>

<div
	class="fixed inset-0 z-60 flex flex-col items-center justify-center bg-black/70 px-6"
	transition:fade={{ duration: 150 }}
>
	<p class="mb-1 text-xs font-bold tracking-wide text-white/60 uppercase">
		rolling for <span class="text-white/40">(animejs)</span>
	</p>
	<p class="mb-6 max-w-full truncate text-xl font-bold text-white">{itemName}</p>

	<div
		bind:this={windowEl}
		class="relative h-16 w-full max-w-[360px] overflow-hidden rounded-2xl border-4 border-black bg-gray-50"
	>
		<div class="pointer-events-none absolute inset-y-0 left-1/2 z-10 w-0 -translate-x-1/2">
			<div
				class="absolute top-0 left-1/2 h-2.5 w-5 -translate-x-1/2 rounded-b-full border-2 border-t-0 border-black bg-yellow-400"
			></div>
			<div
				class="absolute bottom-0 left-1/2 h-2.5 w-5 -translate-x-1/2 rounded-t-full border-2 border-b-0 border-black bg-yellow-400"
			></div>
		</div>

		<div
			class="flex h-full items-center gap-[10px] px-[10px]"
			style="transform: translateX({translateX}px)"
		>
			{#each tiles as n, i (i)}
				{@const isLanded = phase === 'settled' && i === targetIndex}
				<div
					class="flex h-[46px] w-[60px] shrink-0 items-center justify-center rounded-xl border-2 border-black font-bold transition-all duration-300 {isLanded
						? won
							? 'scale-110 border-green-600 bg-green-500 text-white ring-4 ring-yellow-400'
							: 'scale-110 border-red-600 bg-red-500 text-white ring-4 ring-yellow-400'
						: n <= winThreshold
							? 'bg-green-50'
							: 'bg-white'}"
				>
					{n}
				</div>
			{/each}
		</div>
	</div>

	<p class="mt-6 text-sm font-bold text-white/70">
		{#if phase === 'settled'}
			{won ? 'you won!' : 'so close!'}
		{:else}
			rolling…
		{/if}
	</p>
</div>
