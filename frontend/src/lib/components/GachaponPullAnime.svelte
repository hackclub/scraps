<script lang="ts">
	// Comparison twin of GachaponPull.svelte: same capsule rise → shake →
	// crack open → prize pop sequence, same visual pieces and timing targets,
	// but sequenced with anime.js's createTimeline() driving bound DOM
	// elements directly instead of CSS @keyframes + class-toggle transitions.
	// Not wired into any real flow — exists so the two can be judged side by
	// side. If one wins, port its approach into GachaponPull.svelte and
	// delete the other; don't keep both live long-term.
	import { onMount, onDestroy } from 'svelte';
	import { fade } from 'svelte/transition';
	import { Spool } from '@lucide/svelte';
	import { createTimeline, cubicBezier, type Timeline } from 'animejs';

	let {
		itemName,
		itemImage,
		gachaponName,
		onDone
	}: {
		itemName: string;
		itemImage: string | null;
		gachaponName: string;
		onDone: () => void;
	} = $props();

	type Phase = 'rising' | 'shaking' | 'cracking' | 'revealed';
	let phase = $state<Phase>('rising');

	let capsuleEl: HTMLDivElement;
	let topEl: HTMLSpanElement;
	let bottomEl: HTMLSpanElement;
	let seamEl: HTMLSpanElement;
	let burstEl: HTMLDivElement;
	let prizeEl: HTMLDivElement;

	let tl: Timeline | null = null;

	onMount(() => {
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

		// Same relative pacing as GachaponPull's step schedule, just scaled way
		// down under reduced motion instead of hand-listing a second schedule.
		const k = reduce ? 0.03 : 1;
		const d = (ms: number) => Math.max(2, Math.round(ms * k));
		const hold = reduce ? 20 : 1000;

		tl = createTimeline({ autoplay: true }).add(capsuleEl, {
			translateY: ['150%', '0%'],
			duration: d(700),
			ease: cubicBezier(0.2, 0.8, 0.3, 1)
		});

		tl.add(capsuleEl, {
			onBegin: () => (phase = 'shaking'),
			keyframes: [
				{ translateX: 0, rotate: 0, duration: 0 },
				{ translateX: -6, rotate: -4, duration: d(120) },
				{ translateX: 6, rotate: 4, duration: d(120) },
				{ translateX: -4, rotate: -3, duration: d(120) },
				{ translateX: 4, rotate: 3, duration: d(120) },
				{ translateX: 0, rotate: 0, duration: d(120) }
			],
			ease: 'inOutQuad'
		});

		tl.add(
			topEl,
			{
				onBegin: () => (phase = 'cracking'),
				translateX: -46,
				translateY: -66,
				rotate: -38,
				opacity: 0,
				duration: d(500),
				ease: 'outCubic'
			},
			'<'
		)
			.add(
				bottomEl,
				{
					translateX: 46,
					translateY: 66,
					rotate: 38,
					opacity: 0,
					duration: d(500),
					ease: 'outCubic'
				},
				'<'
			)
			.add(seamEl, { opacity: 0, duration: d(300) }, '<')
			.add(
				burstEl,
				{ scale: [0.2, 6], opacity: [0.9, 0], duration: d(550), ease: 'outCubic' },
				'<'
			);

		tl.add(prizeEl, {
			onBegin: () => (phase = 'revealed'),
			scale: [0.1, 1],
			opacity: [0, 1],
			duration: d(500),
			ease: cubicBezier(0.2, 1.3, 0.4, 1),
			onComplete: () => setTimeout(onDone, hold)
		});
	});

	onDestroy(() => {
		tl?.pause();
	});
</script>

<div
	class="fixed inset-0 z-[60] flex flex-col items-center justify-center bg-black/70 px-6"
	transition:fade={{ duration: 150 }}
>
	<p class="mb-2 text-sm font-bold tracking-wide text-white/70 uppercase">
		{gachaponName} <span class="text-white/40">(animejs)</span>
	</p>

	<div class="capsule-stage">
		<div bind:this={capsuleEl} class="capsule" style="transform: translateY(150%)">
			<span bind:this={topEl} class="capsule-half capsule-top"></span>
			<span bind:this={bottomEl} class="capsule-half capsule-bottom"></span>
			<span bind:this={seamEl} class="capsule-seam"></span>
		</div>

		<div bind:this={burstEl} class="burst"></div>

		<div bind:this={prizeEl} class="prize">
			{#if itemImage}
				<img src={itemImage} alt={itemName} />
			{:else}
				<div class="prize-fallback"><Spool size={40} /></div>
			{/if}
		</div>
	</div>

	{#if phase === 'revealed'}
		<div class="mt-6 text-center" in:fade={{ duration: 200, delay: 120 }}>
			<p class="text-xs font-bold tracking-wide text-white/60 uppercase">you got</p>
			<p class="text-2xl font-bold text-white">{itemName}</p>
		</div>
	{:else}
		<p class="mt-6 text-sm font-bold text-white/70">
			{phase === 'rising' ? 'loading capsule…' : 'cracking it open…'}
		</p>
	{/if}
</div>

<style>
	.capsule-stage {
		position: relative;
		width: 200px;
		height: 200px;
		display: flex;
		align-items: center;
		justify-content: center;
		overflow: visible;
	}

	.capsule {
		position: relative;
		width: 150px;
		height: 150px;
	}

	.capsule-half {
		position: absolute;
		left: 0;
		width: 150px;
		height: 75px;
		border: 4px solid #000;
		box-sizing: border-box;
	}

	.capsule-top {
		top: 0;
		border-radius: 75px 75px 0 0;
		border-bottom: none;
		background: linear-gradient(160deg, #f87171, #dc2626);
	}

	.capsule-bottom {
		bottom: 0;
		border-radius: 0 0 75px 75px;
		border-top: none;
		background: linear-gradient(160deg, #fde68a, #fbbf24);
	}

	.capsule-seam {
		position: absolute;
		top: 50%;
		left: -6px;
		width: 162px;
		height: 12px;
		margin-top: -6px;
		border: 4px solid #000;
		border-radius: 6px;
		background: #fff;
	}

	.burst {
		position: absolute;
		width: 40px;
		height: 40px;
		border-radius: 999px;
		background: #fff;
		opacity: 0;
	}

	.prize {
		position: absolute;
		width: 130px;
		height: 130px;
		display: flex;
		align-items: center;
		justify-content: center;
		opacity: 0;
	}

	.prize img {
		max-width: 100%;
		max-height: 100%;
		object-fit: contain;
		filter: drop-shadow(0 6px 10px rgba(0, 0, 0, 0.4));
	}

	.prize-fallback {
		width: 100%;
		height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		border: 4px solid #fff;
		border-radius: 16px;
		color: #fff;
	}
</style>
