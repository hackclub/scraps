<script lang="ts">
	// A small black-and-white checkmark that rises and fades — a quiet success
	// confirmation (e.g. after a refinery upgrade). Extracted out of
	// refinery/+page.svelte so it isn't duplicated by hand anywhere that wants
	// to reuse or compare it (see UpgradeCheckmarkAnime.svelte). Render it
	// absolutely positioned inside a `position: relative` ancestor. Fires
	// onDone once its own animation finishes, so callers don't separately
	// track the 900ms duration themselves.
	import { onMount } from 'svelte';
	import { Check } from '@lucide/svelte';

	let { onDone }: { onDone: () => void } = $props();

	onMount(() => {
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
		const timer = setTimeout(onDone, reduce ? 10 : 900);
		return () => clearTimeout(timer);
	});
</script>

<span class="upgrade-check" aria-hidden="true">
	<Check size={16} strokeWidth={3} />
</span>

<style>
	.upgrade-check {
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
		animation: upgrade-check-rise 900ms ease-out forwards;
	}

	@keyframes upgrade-check-rise {
		0% {
			transform: translateY(4px) scale(0.6);
			opacity: 0;
		}
		20% {
			transform: translateY(0) scale(1.05);
			opacity: 1;
		}
		35% {
			transform: translateY(0) scale(1);
			opacity: 1;
		}
		100% {
			transform: translateY(-26px) scale(1);
			opacity: 0;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.upgrade-check {
			animation-duration: 0.01ms;
		}
	}
</style>
