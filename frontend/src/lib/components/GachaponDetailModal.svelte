<script lang="ts">
	import { fade, scale, slide } from 'svelte/transition';
	import { X, Spool, ChevronDown } from '@lucide/svelte';

	interface GachaItem {
		id: number;
		name: string;
		image: string;
		count: number;
		pullChance: number;
	}
	interface Gachapon {
		id: number;
		name: string;
		description: string | null;
		price: number;
		items: GachaItem[];
	}

	let {
		gachapon,
		domeColor,
		pulling = false,
		onPull,
		onClose
	}: {
		gachapon: Gachapon;
		domeColor: string;
		pulling?: boolean;
		onPull: () => void;
		onClose: () => void;
	} = $props();

	let inStock = $derived(gachapon.items.filter((i) => i.count !== 0));
	let twitching = $state(false);
	let expanded = $state(false);

	function stockLabel(count: number): string {
		if (count === 0) return 'sold out';
		if (count < 0) return '∞';
		return `${count} left`;
	}

	function scatter(id: number, i: number, n: number) {
		const rnd = (k: number) => {
			const x = Math.sin(id * (k + 1) * 12.9898 + i * 4.1414) * 43758.5453;
			return x - Math.floor(x);
		};
		const slots = Math.max(n, 1);
		const slice = 100 / slots;
		const base = n <= 2 ? 104 : n <= 3 ? 90 : n <= 4 ? 78 : n <= 5 ? 68 : 58;
		return {
			left: Math.min(85, Math.max(15, (i + 0.5) * slice + (rnd(0) - 0.5) * slice * 0.6)),
			top: 44 + (rnd(1) - 0.5) * 46,
			rot: rnd(2) * 32 - 16,
			size: base + Math.round(rnd(3) * 12)
		};
	}

	function handlePull() {
		if (pulling || twitching || inStock.length === 0) return;
		twitching = true;
		setTimeout(() => {
			twitching = false;
			onPull();
		}, 380);
	}
</script>

<div
	class="fixed inset-0 z-[55] flex items-center justify-center bg-black/60 p-4"
	onclick={(e) => e.target === e.currentTarget && onClose()}
	onkeydown={(e) => e.key === 'Escape' && onClose()}
	role="dialog"
	tabindex="-1"
	transition:fade={{ duration: 150 }}
>
	<div
		class="relative max-h-[90vh] w-full max-w-md overflow-hidden rounded-2xl border-4 border-black bg-white"
		style="--dome:{domeColor}"
		transition:scale={{ duration: 200, start: 0.94 }}
	>
		<button
			onclick={onClose}
			aria-label="Close"
			class="absolute top-3 right-3 z-10 flex h-8 w-8 cursor-pointer items-center justify-center rounded-full border-2 border-black bg-white transition-all hover:border-dashed"
		>
			<X size={16} />
		</button>

		<div class="gd-dome" class:twitch={twitching}>
			{#each gachapon.items.slice(0, 7) as item, i (item.id)}
				{@const s = scatter(item.id, i, Math.min(gachapon.items.length, 7))}
				<div
					class="gd-scatter {item.count === 0 ? 'opacity-30 grayscale' : ''}"
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

		<div class="h-3 bg-black"></div>

		<div
			class="overflow-y-auto p-5"
			style="max-height: calc(90vh - 12rem); background: color-mix(in srgb, var(--dome) 14%, #fff)"
		>
			<h2 class="text-2xl font-bold">{gachapon.name}</h2>
			{#if gachapon.description}
				<p class="mt-1 text-sm text-gray-600">{gachapon.description}</p>
			{/if}

			<button
				type="button"
				onclick={() => (expanded = !expanded)}
				class="mt-3 flex w-full cursor-pointer items-center justify-between rounded-lg border-2 border-black bg-white px-3 py-2 text-sm font-bold transition-all hover:border-dashed"
			>
				<span>see what you can get ({gachapon.items.length})</span>
				<ChevronDown
					size={18}
					class="transition-transform duration-200 {expanded ? 'rotate-180' : ''}"
				/>
			</button>

			{#if expanded}
				<div class="mt-2 space-y-1.5" transition:slide={{ duration: 180 }}>
					{#each [...gachapon.items].sort((a, b) => b.pullChance - a.pullChance) as item (item.id)}
						<div
							class="flex items-center gap-3 rounded-lg border-2 border-black bg-white p-2 {item.count ===
							0
								? 'opacity-50'
								: ''}"
						>
							{#if item.image}
								<img
									src={item.image}
									alt={item.name}
									class="h-10 w-10 shrink-0 rounded-lg border-2 border-black bg-white object-contain"
								/>
							{:else}
								<div
									class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border-2 border-black bg-white"
								>
									<Spool size={16} class="text-gray-400" />
								</div>
							{/if}
							<span class="flex-1 truncate text-sm font-bold">{item.name}</span>
							<span class="text-xs text-gray-500">{stockLabel(item.count)}</span>
							<span
								class="shrink-0 rounded-full bg-indigo-100 px-2 py-0.5 text-xs font-bold text-indigo-700"
							>
								{item.count === 0 ? '·' : `${item.pullChance}%`}
							</span>
						</div>
					{/each}
				</div>
			{/if}

			<button
				onclick={handlePull}
				disabled={pulling || twitching || inStock.length === 0}
				class="mt-4 flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-3 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
			>
				<Spool size={18} />
				{inStock.length === 0
					? 'sold out'
					: pulling || twitching
						? 'pulling…'
						: `pull for ${gachapon.price}`}
			</button>
		</div>
	</div>
</div>

<style>
	.gd-dome {
		position: relative;
		height: 10rem;
		border-bottom: 4px solid #000;
		border-radius: 999px 999px 0 0 / 90% 90% 0 0;
		background:
			radial-gradient(circle at 32% 24%, rgba(255, 255, 255, 0.92), transparent 46%),
			color-mix(in srgb, var(--dome) 30%, #fff);
		overflow: hidden;
	}

	.gd-scatter {
		position: absolute;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.gd-scatter img {
		width: 100%;
		height: 100%;
		object-fit: contain;
		filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.25));
	}

	.twitch {
		animation: twitch 0.38s ease-in-out;
	}

	@keyframes twitch {
		0%,
		100% {
			transform: translateX(0) rotate(0);
		}
		20% {
			transform: translateX(-4px) rotate(-1.5deg);
		}
		45% {
			transform: translateX(4px) rotate(1.5deg);
		}
		70% {
			transform: translateX(-3px) rotate(-1deg);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.twitch {
			animation-duration: 0.01ms;
		}
	}
</style>
