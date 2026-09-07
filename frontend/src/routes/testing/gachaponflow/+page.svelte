<script lang="ts">
	import { onMount } from 'svelte';
	import { API_URL } from '$lib/config';
	import { getUser } from '$lib/auth-client';
	import { Spool, RotateCcw, Sparkles } from '@lucide/svelte';
	import GachaponPull from '$lib/components/GachaponPull.svelte';
	import GachaponDetailModal from '$lib/components/GachaponDetailModal.svelte';

	interface GachaItem {
		id: number;
		name: string;
		image: string;
		count: number;
		price: number;
		pullChance: number;
	}
	interface Gachapon {
		id: number;
		name: string;
		description: string | null;
		price: number;
		items: GachaItem[];
	}

	const domeColors = ['#f87171', '#fbbf24', '#60a5fa', '#c084fc', '#4ade80'];

	let gachapons = $state<Gachapon[]>([]);
	let loading = $state(true);
	let twitchingId = $state<number | null>(null);
	let detailGachapon = $state<Gachapon | null>(null);
	let reveal = $state<{ name: string; image: string | null; gachaponName: string } | null>(null);
	let lastPull = $state<{ gachapon: string; item: GachaItem } | null>(null);
	let history = $state<{ gachapon: string; item: string }[]>([]);

	function domeFor(g: Gachapon) {
		const i = gachapons.findIndex((x) => x.id === g.id);
		return domeColors[(i < 0 ? 0 : i) % domeColors.length];
	}

	function scatter(id: number, i: number, n: number) {
		const rnd = (k: number) => {
			const x = Math.sin(id * (k + 1) * 12.9898 + i * 4.1414) * 43758.5453;
			return x - Math.floor(x);
		};
		const slots = Math.max(n, 1);
		const slice = 100 / slots;
		const base = n <= 2 ? 116 : n <= 3 ? 98 : n <= 4 ? 84 : n <= 5 ? 74 : 64;
		return {
			left: Math.min(86, Math.max(14, (i + 0.5) * slice + (rnd(0) - 0.5) * slice * 0.6)),
			top: 32 + (rnd(1) - 0.5) * 42,
			rot: rnd(2) * 32 - 16,
			size: base + Math.round(rnd(3) * 14)
		};
	}

	function pickWinner(g: Gachapon): GachaItem | null {
		const pool = g.items.filter((i) => i.count !== 0);
		if (pool.length === 0) return null;
		const weights = pool.map((i) => 1 / Math.sqrt(Math.max(i.price ?? 1, 1)));
		const total = weights.reduce((a, b) => a + b, 0);
		let t = Math.random() * total;
		for (let k = 0; k < pool.length; k++) {
			t -= weights[k];
			if (t < 0) return pool[k];
		}
		return pool[pool.length - 1];
	}

	function doPull(g: Gachapon) {
		if (twitchingId === g.id || reveal) return;
		const winner = pickWinner(g);
		if (!winner) return;
		twitchingId = g.id;
		detailGachapon = null;
		setTimeout(() => {
			twitchingId = null;
			lastPull = { gachapon: g.name, item: winner };
			reveal = { name: winner.name, image: winner.image || null, gachaponName: g.name };
		}, 380);
	}

	function finishReveal() {
		if (lastPull) {
			history = [{ gachapon: lastPull.gachapon, item: lastPull.item.name }, ...history].slice(
				0,
				12
			);
		}
		reveal = null;
	}

	function replay() {
		if (!lastPull) return;
		reveal = {
			name: lastPull.item.name,
			image: lastPull.item.image || null,
			gachaponName: lastPull.gachapon
		};
	}

	onMount(async () => {
		await getUser();
		try {
			const res = await fetch(`${API_URL}/shop/gachapons`, { credentials: 'include' });
			if (res.ok) gachapons = await res.json();
		} catch (e) {
			console.error('failed to load gachapons', e);
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head>
	<title>gachapon flow sandbox - scraps</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-2 flex items-center gap-2">
		<Sparkles size={28} />
		<h1 class="text-4xl font-bold md:text-5xl">gachapon flow</h1>
	</div>
	<p class="mb-6 text-lg text-gray-600">
		Live gachapons from <code>/shop/gachapons</code>. Pull is mocked: no backend, no scraps, no
		address step. Winner is picked locally, weighted 1/√price like the real endpoint.
	</p>

	<div class="mb-8 flex flex-wrap items-center gap-3">
		<button
			onclick={replay}
			disabled={!lastPull}
			class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-4 py-2 text-sm font-bold transition-all hover:border-dashed disabled:opacity-40"
		>
			<RotateCcw size={16} /> replay last reveal
		</button>
		{#if lastPull}
			<span class="text-sm text-gray-600">
				last: <strong>{lastPull.item.name}</strong> from {lastPull.gachapon}
			</span>
		{/if}
	</div>

	{#if loading}
		<div class="py-12 text-center text-gray-500">loading…</div>
	{:else if gachapons.length === 0}
		<p class="rounded-2xl border-4 border-dashed border-gray-300 p-8 text-center text-gray-400">
			no gachapons: create one in admin → shop
		</p>
	{:else}
		<div class="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-3">
			{#each gachapons as gachapon, gi (gachapon.id)}
				{@const inStock = gachapon.items.filter((i) => i.count !== 0)}
				{@const dome = domeColors[gi % domeColors.length]}
				<div
					class="gachapon-machine"
					class:twitch={twitchingId === gachapon.id}
					style="--dome:{dome}"
				>
					<button
						type="button"
						onclick={() => (detailGachapon = gachapon)}
						class="gachapon-globe cursor-pointer"
						title="see what's inside"
					>
						<div class="gachapon-globe-inner">
							{#each gachapon.items.slice(0, 6) as item, i (item.id)}
								{@const s = scatter(item.id, i, Math.min(gachapon.items.length, 6))}
								<div
									class="gachapon-scatter {item.count === 0 ? 'opacity-30 grayscale' : ''}"
									style="left:{s.left}%; top:{s.top}%; width:{s.size}px; height:{s.size}px; transform: translate(-50%, -50%) rotate({s.rot}deg)"
									title={item.name}
								>
									{#if item.image}
										<img src={item.image} alt={item.name} />
									{:else}
										<Spool size={s.size * 0.5} class="text-gray-400" />
									{/if}
								</div>
							{/each}
						</div>
						<span class="gachapon-glass"></span>
					</button>

					<div class="gachapon-body">
						<h3 class="text-lg font-bold">{gachapon.name}</h3>
						{#if gachapon.description}
							<p class="mt-0.5 text-sm text-gray-600">{gachapon.description}</p>
						{/if}
						<div class="mt-3 flex items-center gap-3">
							<button
								onclick={() => doPull(gachapon)}
								disabled={twitchingId === gachapon.id || inStock.length === 0 || !!reveal}
								class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
							>
								<Spool size={18} />
								{inStock.length === 0
									? 'sold out'
									: twitchingId === gachapon.id
										? 'pulling…'
										: 'test pull'}
							</button>
							<span class="gachapon-knob" aria-hidden="true"></span>
						</div>
					</div>
				</div>
			{/each}
		</div>

		{#if history.length > 0}
			<h2 class="mt-12 mb-2 text-xl font-bold">pull history</h2>
			<ul class="space-y-1 text-sm text-gray-600">
				{#each history as h, i (i)}
					<li><strong>{h.item}</strong>: {h.gachapon}</li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>

{#if detailGachapon && !reveal}
	<GachaponDetailModal
		gachapon={detailGachapon}
		domeColor={domeFor(detailGachapon)}
		onPull={() => detailGachapon && doPull(detailGachapon)}
		onClose={() => (detailGachapon = null)}
	/>
{/if}

{#if reveal}
	<GachaponPull
		itemName={reveal.name}
		itemImage={reveal.image}
		gachaponName={reveal.gachaponName}
		onDone={finishReveal}
	/>
{/if}

<style>
	.gachapon-machine {
		display: flex;
		flex-direction: column;
		border: 4px solid #000;
		border-radius: 6rem 6rem 1rem 1rem;
		background: color-mix(in srgb, var(--dome) 22%, #fff);
		overflow: hidden;
	}

	.gachapon-machine.twitch {
		animation: machine-twitch 0.38s ease-in-out;
	}

	@keyframes machine-twitch {
		0%,
		100% {
			transform: translateX(0) rotate(0);
		}
		20% {
			transform: translateX(-4px) rotate(-1.2deg);
		}
		45% {
			transform: translateX(4px) rotate(1.2deg);
		}
		70% {
			transform: translateX(-3px) rotate(-0.8deg);
		}
	}

	.gachapon-globe {
		position: relative;
		display: block;
		width: 100%;
		margin: 0;
		height: 12rem;
		border: none;
		border-bottom: 4px solid #000;
		border-radius: 0;
		background:
			radial-gradient(circle at 30% 22%, rgba(255, 255, 255, 0.92), transparent 48%),
			color-mix(in srgb, var(--dome) 26%, #fff);
	}

	.gachapon-globe-inner {
		position: absolute;
		inset: 0.4rem 0.3rem 0.3rem;
		overflow: hidden;
	}

	.gachapon-scatter {
		position: absolute;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.gachapon-scatter img {
		width: 100%;
		height: 100%;
		object-fit: contain;
		filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.25));
	}

	.gachapon-glass {
		position: absolute;
		inset: 0;
		pointer-events: none;
		box-shadow: inset 0 -0.6rem 1rem rgba(0, 0, 0, 0.12);
	}

	.gachapon-body {
		position: relative;
		padding: 1rem 1.25rem 1.25rem;
		background: color-mix(in srgb, var(--dome) 22%, #fff);
	}

	.gachapon-knob {
		position: relative;
		display: block;
		width: 2.25rem;
		height: 2.25rem;
		flex-shrink: 0;
		border: 4px solid #000;
		border-radius: 999px;
		background: #fff;
		transition: transform 0.2s ease;
	}

	.gachapon-knob::after {
		content: '';
		position: absolute;
		top: 50%;
		left: 50%;
		width: 4px;
		height: 0.85rem;
		transform: translate(-50%, -50%);
		border-radius: 2px;
		background: #000;
	}

	.gachapon-machine.twitch .gachapon-knob {
		transform: rotate(150deg);
	}

	@media (prefers-reduced-motion: reduce) {
		.gachapon-machine.twitch {
			animation-duration: 0.01ms;
		}
	}
</style>
