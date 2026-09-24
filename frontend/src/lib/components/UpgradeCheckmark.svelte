<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { Check } from '@lucide/svelte';
	import { animate, type JSAnimation } from 'animejs';

	let { onDone }: { onDone: () => void } = $props();

	let y = $state(6);
	let scale = $state(0.6);
	let opacity = $state(0);
	let anim: JSAnimation | null = null;

	onMount(() => {
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

		const state = { y: 6, scale: 0.6, opacity: 0 };
		anim = animate(state, {
			keyframes: [
				{ y: 0, scale: 1.08, opacity: 1, duration: reduce ? 2 : 180 },
				{ y: 0, scale: 1, duration: reduce ? 2 : 135 },
				{ y: -34, scale: 1, opacity: 0, duration: reduce ? 6 : 585 }
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
	class="upgrade-check"
	aria-hidden="true"
	style="transform: translateY({y}px) scale({scale}); opacity: {opacity}"
>
	<Check size={20} strokeWidth={3} />
</span>

<style>
	.upgrade-check {
		position: absolute;
		top: -10px;
		right: 0;
		z-index: 10;
		display: flex;
		align-items: center;
		justify-content: center;
		width: 34px;
		height: 34px;
		border-radius: 999px;
		border: 2px solid #000;
		background: #000;
		color: #fff;
		pointer-events: none;
	}
</style>
