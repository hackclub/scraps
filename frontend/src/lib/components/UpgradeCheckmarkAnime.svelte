<script lang="ts">
	// Comparison twin of UpgradeCheckmark.svelte: identical look/positioning,
	// but the rise-and-fade is driven by anime.js's animate() with an explicit
	// duration-keyframes list instead of a single CSS @keyframes rule. Not
	// wired into any real flow — exists so the two can be judged side by
	// side. If one wins, port its approach and delete the other.
	import { onMount, onDestroy } from 'svelte';
	import { Check } from '@lucide/svelte';
	import { animate, type JSAnimation } from 'animejs';

	let { onDone }: { onDone: () => void } = $props();

	let y = $state(4);
	let scale = $state(0.6);
	let opacity = $state(0);
	let anim: JSAnimation | null = null;

	onMount(() => {
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

		// Mirrors the original's three CSS keyframe stops (pop in past 1x,
		// settle to 1x, rise + fade out) as three duration-keyframes.
		const state = { y: 4, scale: 0.6, opacity: 0 };
		anim = animate(state, {
			keyframes: [
				{ y: 0, scale: 1.05, opacity: 1, duration: reduce ? 2 : 180 },
				{ y: 0, scale: 1, duration: reduce ? 2 : 135 },
				{ y: -26, scale: 1, opacity: 0, duration: reduce ? 6 : 585 }
			],
			ease: 'outCubic',
			onUpdate: () => {
				y = state.y;
				scale = state.scale;
				opacity = state.opacity;
			},
			onComplete: () => onDone()
		});
	});

	onDestroy(() => {
		anim?.pause();
	});
</script>

<span
	class="upgrade-check-anime"
	aria-hidden="true"
	style="transform: translateY({y}px) scale({scale}); opacity: {opacity}"
>
	<Check size={16} strokeWidth={3} />
</span>

<style>
	.upgrade-check-anime {
		position: absolute;
		top: -6px;
		right: 0;
		z-index: 10;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 26px;
		height: 26px;
		border-radius: 999px;
		border: 2px solid #000;
		background: #000;
		color: #fff;
		pointer-events: none;
	}
</style>
