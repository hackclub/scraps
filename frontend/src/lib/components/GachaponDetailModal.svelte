<script lang="ts">
	import { fade, scale, slide } from 'svelte/transition';
	import { X, Spool, ChevronDown, HelpCircle } from '@lucide/svelte';

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
		image: string | null;
		price: number;
		items: GachaItem[];
	}

	let {
		gachapon,
		pulling = false,
		onPull,
		onClose
	}: {
		gachapon: Gachapon;
		pulling?: boolean;
		onPull: () => void;
		onClose: () => void;
	} = $props();

	let inStock = $derived(gachapon.items.filter((i) => i.count !== 0));
	let expanded = $state(false);

	function stockLabel(count: number): string {
		if (count === 0) return 'sold out';
		if (count < 0) return '∞';
		return `${count} left`;
	}

	function handlePull() {
		if (pulling || inStock.length === 0) return;
		onPull();
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
		transition:scale={{ duration: 200, start: 0.94 }}
	>
		<button
			onclick={onClose}
			aria-label="Close"
			class="absolute top-3 right-3 z-10 flex h-8 w-8 cursor-pointer items-center justify-center rounded-full border-2 border-black bg-white transition-all hover:border-dashed"
		>
			<X size={16} />
		</button>

		<div class="flex h-40 items-center justify-center border-b-4 border-black bg-gray-50">
			{#if gachapon.image}
				<img
					src={gachapon.image}
					alt={gachapon.name}
					class="h-full w-full object-contain p-4"
				/>
			{:else}
				<HelpCircle size={64} strokeWidth={2.5} class="text-gray-400" />
			{/if}
		</div>

		<div class="overflow-y-auto p-5" style="max-height: calc(90vh - 10rem)">
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
				disabled={pulling || inStock.length === 0}
				class="mt-4 flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-3 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
			>
				<Spool size={18} />
				{inStock.length === 0 ? 'sold out' : pulling ? 'pulling…' : `pull for ${gachapon.price}`}
			</button>
		</div>
	</div>
</div>
