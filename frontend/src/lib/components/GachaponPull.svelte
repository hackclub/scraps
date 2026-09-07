<script lang="ts">
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';
	import { Spool } from '@lucide/svelte';

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

	onMount(() => {
		const reduce =
			typeof window !== 'undefined' &&
			window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

		const steps: [Phase | 'done', number][] = reduce
			? [
					['shaking', 40],
					['cracking', 90],
					['revealed', 140],
					['done', 260]
				]
			: [
					['shaking', 750],
					['cracking', 1450],
					['revealed', 2050],
					['done', 3050]
				];

		const timers = steps.map(([p, at]) =>
			setTimeout(() => (p === 'done' ? onDone() : (phase = p)), at)
		);
		return () => timers.forEach(clearTimeout);
	});
</script>

<div
	class="fixed inset-0 z-[60] flex flex-col items-center justify-center bg-black/70 px-6"
	transition:fade={{ duration: 150 }}
>
	<p class="mb-2 text-sm font-bold tracking-wide text-white/70 uppercase">{gachaponName}</p>

	<div class="capsule-stage">
		<div
			class="capsule"
			class:is-rising={phase === 'rising'}
			class:is-shaking={phase === 'shaking'}
			class:is-open={phase === 'cracking' || phase === 'revealed'}
		>
			<span class="capsule-half capsule-top"></span>
			<span class="capsule-half capsule-bottom"></span>
			<span class="capsule-seam"></span>
		</div>

		{#if phase === 'cracking' || phase === 'revealed'}
			<div class="burst"></div>
		{/if}

		{#if phase === 'revealed'}
			<div class="prize" in:fade={{ duration: 200 }}>
				{#if itemImage}
					<img src={itemImage} alt={itemName} />
				{:else}
					<div class="prize-fallback"><Spool size={40} /></div>
				{/if}
			</div>
		{/if}
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
		transition:
			transform 0.5s cubic-bezier(0.3, -0.4, 0.6, 1.4),
			opacity 0.5s ease;
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
		transition: opacity 0.3s ease;
	}

	.capsule.is-rising {
		animation: rise 0.7s cubic-bezier(0.2, 0.8, 0.3, 1) both;
	}

	.capsule.is-shaking {
		animation: shake 0.6s ease-in-out;
	}

	.capsule.is-open .capsule-top {
		transform: translate(-46px, -66px) rotate(-38deg);
		opacity: 0;
	}

	.capsule.is-open .capsule-bottom {
		transform: translate(46px, 66px) rotate(38deg);
		opacity: 0;
	}

	.capsule.is-open .capsule-seam {
		opacity: 0;
	}

	.burst {
		position: absolute;
		width: 40px;
		height: 40px;
		border-radius: 999px;
		background: #fff;
		animation: burst 0.55s ease-out forwards;
	}

	.prize {
		position: absolute;
		width: 130px;
		height: 130px;
		display: flex;
		align-items: center;
		justify-content: center;
		animation: pop 0.5s cubic-bezier(0.2, 1.3, 0.4, 1) both;
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

	@keyframes rise {
		from {
			transform: translateY(150%);
		}
		to {
			transform: translateY(0);
		}
	}

	@keyframes shake {
		0%,
		100% {
			transform: translateX(0) rotate(0);
		}
		20% {
			transform: translateX(-6px) rotate(-4deg);
		}
		40% {
			transform: translateX(6px) rotate(4deg);
		}
		60% {
			transform: translateX(-4px) rotate(-3deg);
		}
		80% {
			transform: translateX(4px) rotate(3deg);
		}
	}

	@keyframes burst {
		from {
			transform: scale(0.2);
			opacity: 0.9;
		}
		to {
			transform: scale(6);
			opacity: 0;
		}
	}

	@keyframes pop {
		from {
			transform: scale(0.1);
			opacity: 0;
		}
		to {
			transform: scale(1);
			opacity: 1;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.capsule.is-rising,
		.capsule.is-shaking,
		.burst,
		.prize {
			animation-duration: 0.01ms;
		}
	}
</style>
