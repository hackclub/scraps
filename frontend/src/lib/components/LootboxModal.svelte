<script lang="ts">
	import { X, Spool, Package } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { refreshUserScraps, userScrapsStore } from '$lib/auth-client';
	import HeartButton from './HeartButton.svelte';
	import { t } from '$lib/i18n';

	interface LootboxItemData {
		shopItemId: number;
		percentage: number;
		itemName: string;
		itemImage: string;
		itemPrice: number;
		itemCount: number;
	}

	interface LootboxData {
		id: number;
		name: string;
		image: string;
		description: string;
		price: number;
		category: string;
		items: LootboxItemData[];
		heartCount: number;
		userHearted: boolean;
	}

	let {
		lootbox,
		onClose,
		onWin
	}: {
		lootbox: LootboxData;
		onClose: () => void;
		onWin: (orderId: number, wonItemName: string) => void;
	} = $props();

	let boostedItemId = $state<number | null>(null);
	let rolling = $state(false);
	let showConfirmation = $state(false);
	let localHearted = $state(lootbox.userHearted);
	let localHeartCount = $state(lootbox.heartCount);
	let canAfford = $derived($userScrapsStore >= lootbox.price);
	let alertMessage = $state<string | null>(null);
	let alertType = $state<'error' | 'info'>('info');

	let inStockItems = $derived(lootbox.items.filter((i) => i.itemCount > 0));
	let hasInStock = $derived(inStockItems.length > 0);

	let adjustedPercentages = $derived.by(() => {
		if (!boostedItemId) return lootbox.items.map((i) => ({ ...i, adjusted: i.itemCount > 0 ? i.percentage : 0 }));

		const items = lootbox.items.map((i) => ({
			...i,
			adjusted: i.itemCount <= 0 ? 0 : i.shopItemId === boostedItemId ? i.percentage * 2 : i.percentage
		}));

		const total = items.reduce((sum, i) => sum + i.adjusted, 0);
		if (total === 0) return items;

		return items.map((i) => ({
			...i,
			adjusted: Math.round((i.adjusted / total) * 1000) / 10
		}));
	});

	function getProbabilityColor(prob: number): string {
		if (prob >= 30) return 'text-green-600';
		if (prob >= 15) return 'text-yellow-600';
		return 'text-red-600';
	}

	async function handleToggleHeart() {
		try {
			const response = await fetch(`${API_URL}/shop/lootboxes/${lootbox.id}/heart`, {
				method: 'POST',
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				localHearted = data.hearted;
				localHeartCount = data.heartCount;
			}
		} catch (e) {
			console.error('Failed to toggle heart:', e);
		}
	}

	async function handleRoll() {
		if (!boostedItemId) return;
		rolling = true;
		try {
			const response = await fetch(`${API_URL}/shop/lootboxes/${lootbox.id}/roll`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ boostedShopItemId: boostedItemId })
			});
			const data = await response.json();

			if (!response.ok) {
				alertType = 'error';
				alertMessage = data.error || 'Failed to open lootbox';
				return;
			}

			await refreshUserScraps();
			if (data.won && data.wonItem) {
				onWin(data.orderId, data.wonItem.name);
			}
		} catch (e) {
			console.error('Failed to roll lootbox:', e);
			alertType = 'error';
			alertMessage = $t.shop.somethingWentWrong;
		} finally {
			rolling = false;
			showConfirmation = false;
		}
	}

	function handleBackdropClick(e: MouseEvent) {
		if (e.target === e.currentTarget) {
			if (showConfirmation) {
				showConfirmation = false;
			} else {
				onClose();
			}
		}
	}
</script>

<div
	class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
	onclick={handleBackdropClick}
	onkeydown={(e) =>
		e.key === 'Escape' && (showConfirmation ? (showConfirmation = false) : onClose())}
	role="dialog"
	tabindex="-1"
>
	<div
		class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border-4 border-black bg-white p-6"
	>
		<div class="mb-4 flex items-start justify-between">
			<div class="flex items-center gap-2">
				<h2 class="text-2xl font-bold">{lootbox.name}</h2>
				<span
					class="rounded-full border-2 border-purple-600 bg-purple-100 px-2 py-0.5 text-xs font-bold text-purple-700"
					>{$t.lootbox.badge}</span
				>
			</div>
			<button
				onclick={onClose}
				class="cursor-pointer rounded-lg p-1 transition-colors hover:bg-gray-100"
			>
				<X size={24} />
			</button>
		</div>

		<img
			src={lootbox.image}
			alt={lootbox.name}
			class="mb-4 h-48 w-full rounded-lg bg-gray-50 object-contain"
		/>

		<p class="mb-4 text-gray-600">{lootbox.description}</p>

		<div class="mb-4 flex items-center justify-between">
			<div class="flex items-center gap-4">
				<span class="flex items-center gap-1 text-xl font-bold">
					<Spool size={20} />
					{lootbox.price}
				</span>
				<span class="text-sm text-gray-500">
					{lootbox.items.length} {$t.lootbox.items}
				</span>
			</div>
			<HeartButton
				count={localHeartCount}
				hearted={localHearted}
				onclick={() => handleToggleHeart()}
			/>
		</div>

		<div class="mb-4 flex flex-wrap gap-2">
			{#each lootbox.category
				.split(',')
				.map((c) => c.trim())
				.filter(Boolean) as cat}
				<span class="rounded-full bg-gray-100 px-2 py-1 text-xs">{cat}</span>
			{/each}
		</div>

		<!-- Item list with boost selection -->
		<div class="mb-4 rounded-lg border-2 border-black p-4">
			<p class="mb-3 text-sm font-bold">{$t.lootbox.boostHint}</p>
			<div class="space-y-2">
				{#each adjustedPercentages as item}
					{@const isOutOfStock = item.itemCount <= 0}
					{@const isBoosted = item.shopItemId === boostedItemId}
					<label
						class="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition-all {isOutOfStock
							? 'cursor-not-allowed opacity-40'
							: isBoosted
								? 'bg-purple-50 ring-2 ring-purple-400'
								: 'hover:bg-gray-50'}"
					>
						<input
							type="radio"
							name="boost-item"
							value={item.shopItemId}
							checked={isBoosted}
							disabled={isOutOfStock}
							onchange={() => (boostedItemId = item.shopItemId)}
							class="h-4 w-4 cursor-pointer"
						/>
						<img
							src={item.itemImage}
							alt={item.itemName}
							class="h-10 w-10 shrink-0 rounded-lg border border-black object-cover"
						/>
						<div class="flex-1">
							<span class="text-sm font-medium">{item.itemName}</span>
							{#if isOutOfStock}
								<span class="ml-2 text-xs text-red-500">({$t.lootbox.outOfStock})</span>
							{/if}
						</div>
						<div class="text-right">
							<span class="text-sm font-bold {getProbabilityColor(item.adjusted)}">
								{item.adjusted.toFixed(1)}%
							</span>
							{#if isBoosted}
								<span class="ml-1 text-xs font-bold text-purple-600">2x</span>
							{/if}
						</div>
					</label>
				{/each}
			</div>
		</div>

		<!-- Action button -->
		{#if !hasInStock}
			<span
				class="block w-full cursor-not-allowed rounded-full border-4 border-dashed border-gray-300 px-4 py-3 text-center text-lg font-bold text-gray-400"
			>
				{$t.lootbox.allItemsOutOfStock}
			</span>
		{:else}
			<button
				onclick={() => (showConfirmation = true)}
				disabled={rolling || !canAfford || !boostedItemId}
				class="w-full cursor-pointer rounded-full bg-black px-4 py-3 text-lg font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
			>
				{#if !canAfford}
					{$t.shop.notEnoughScraps}
				{:else if !boostedItemId}
					{$t.lootbox.noBoostedItem}
				{:else}
					<span class="flex items-center justify-center gap-2">
						<Package size={20} />
						{$t.lootbox.openLootbox}
					</span>
				{/if}
			</button>
		{/if}
	</div>

	<!-- Confirmation modal -->
	{#if showConfirmation}
		<div
			class="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4"
			onclick={(e) => e.target === e.currentTarget && (showConfirmation = false)}
			onkeydown={(e) => e.key === 'Escape' && (showConfirmation = false)}
			role="dialog"
			tabindex="-1"
		>
			<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
				<h2 class="mb-4 text-2xl font-bold">{$t.lootbox.confirmOpen}</h2>
				<p class="mb-4 text-gray-600">
					{$t.lootbox.confirmOpenMessage}
					<strong>{lootbox.price} {$t.common.scraps}</strong>.
				</p>
				{#if boostedItemId}
					{@const boosted = adjustedPercentages.find((i) => i.shopItemId === boostedItemId)}
					{#if boosted}
						<div class="mb-4 rounded-lg bg-purple-50 p-3">
							<p class="text-sm font-bold text-purple-700">
								{$t.lootbox.boosted}: {boosted.itemName} ({boosted.adjusted.toFixed(1)}%)
							</p>
						</div>
					{/if}
				{/if}
				<div class="flex gap-3">
					<button
						onclick={() => (showConfirmation = false)}
						disabled={rolling}
						class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
					>
						{$t.common.cancel}
					</button>
					<button
						onclick={handleRoll}
						disabled={rolling}
						class="flex-1 cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed disabled:opacity-50"
					>
						{rolling ? $t.lootbox.rolling : $t.lootbox.openLootbox}
					</button>
				</div>
			</div>
		</div>
	{/if}

	<!-- Alert modal -->
	{#if alertMessage}
		<div
			class="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-4"
			onclick={(e) => e.target === e.currentTarget && (alertMessage = null)}
			onkeydown={(e) => e.key === 'Escape' && (alertMessage = null)}
			role="dialog"
			tabindex="-1"
		>
			<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
				<h2 class="mb-4 text-2xl font-bold">
					{alertType === 'error' ? $t.common.error : $t.common.result}
				</h2>
				<p class="mb-6 text-gray-600">{alertMessage}</p>
				<button
					onclick={() => (alertMessage = null)}
					class="w-full cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed"
				>
					{$t.common.ok}
				</button>
			</div>
		</div>
	{/if}
</div>
