<script lang="ts">
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';
	import HeartButton from '$lib/components/HeartButton.svelte';
	import ShopItemModal from '$lib/components/ShopItemModal.svelte';
	import AddressSelectModal from '$lib/components/AddressSelectModal.svelte';
	import { API_URL } from '$lib/config';
	import { getUser } from '$lib/auth-client';
	import { Spool, PackageCheck, Clock, Sparkles, Bookmark, GripVertical, X } from '@lucide/svelte';
	import {
		shopItemsStore,
		shopLoading,
		fetchShopItems,
		updateShopItemHeart,
		showToast,
		type ShopItem
	} from '$lib/stores';
	import { t } from '$lib/i18n';

	const SCRAPS_PER_HOUR = 64;

	function estimateHours(scraps: number): number {
		return Math.round((scraps / SCRAPS_PER_HOUR) * 10) / 10;
	}

	function getItemRollCost(item: ShopItem): number {
		// Prefer the server-provided displayRollCost (authoritative) when available.
		// Fallback to a local computation that mirrors server logic exactly.
		if (item.displayRollCost != null && Number.isFinite(item.displayRollCost)) {
			return item.displayRollCost;
		}
		let baseCost: number;
		if (item.rollCostOverride != null && item.rollCostOverride > 0) {
			baseCost = item.rollCostOverride;
		} else {
			baseCost = Math.max(1, Math.round(item.price * (item.baseProbability / 100)));
		}
		const perRoll = item.perRollMultiplier ?? 0.05;
		return Math.round(baseCost * (1 + perRoll * (item.rollCount || 0)));
	}

	let selectedItem = $state<ShopItem | null>(null);
	let winningOrderId = $state<number | null>(null);
	let winningItemName = $state<string | null>(null);
	let pendingOrders = $state<{ orderId: number; itemName: string }[]>([]);

	let consolationOrderId = $state<number | null>(null);
	let consolationRolled = $state<number | null>(null);
	let consolationNeeded = $state<number | null>(null);

	let dailyDate = $state('');
	let dailyItems = $state<ShopItem[]>([]);
	let dailyLoading = $state(true);
	let revealed = $state(false);

	let retainedItems = $state<ShopItem[]>([]);
	let retainedCap = $state(2);
	let retainedLoading = $state(true);
	let draggingId = $state<number | null>(null);
	let dropHover = $state(false);

	let notInRotation = $derived(
		$shopItemsStore.filter(
			(i) =>
				i.count > 0 &&
				!dailyItems.some((d) => d.id === i.id) &&
				!retainedItems.some((r) => r.id === i.id)
		)
	);

	function seenKey(date: string) {
		return `shop-daily-seen:${date}`;
	}

	async function fetchDaily() {
		dailyLoading = true;
		try {
			const res = await fetch(`${API_URL}/shop/daily`, { credentials: 'include' });
			if (res.ok) {
				const data = await res.json();
				dailyDate = data.date;
				dailyItems = data.items ?? [];
				try {
					revealed = localStorage.getItem(seenKey(dailyDate)) === '1';
				} catch (_e) {
					revealed = false;
				}
			}
		} catch (e) {
			console.error('Failed to load daily items:', e);
		} finally {
			dailyLoading = false;
		}
	}

	async function fetchRetained() {
		retainedLoading = true;
		try {
			const res = await fetch(`${API_URL}/shop/retained`, { credentials: 'include' });
			if (res.ok) {
				const data = await res.json();
				retainedCap = data.cap ?? 2;
				retainedItems = data.items ?? [];
			}
		} catch (e) {
			console.error('Failed to load retained items:', e);
		} finally {
			retainedLoading = false;
		}
	}

	function revealToday() {
		revealed = true;
		try {
			localStorage.setItem(seenKey(dailyDate), '1');
		} catch (_e) {}
	}

	async function retain(itemId: number) {
		if (retainedItems.some((i) => i.id === itemId)) return;
		if (retainedItems.length >= retainedCap) {
			showToast('your permanent shop is full', 'error');
			return;
		}
		try {
			const res = await fetch(`${API_URL}/shop/retained/${itemId}`, {
				method: 'POST',
				credentials: 'include'
			});
			if (res.ok) {
				showToast('kept in your shop for good', 'success');
				fetchRetained();
			} else {
				const data = await res.json().catch(() => ({}));
				showToast(data.error || 'could not save that item', 'error');
			}
		} catch (e) {
			console.error('Failed to retain item:', e);
		}
	}

	async function unretain(itemId: number) {
		try {
			const res = await fetch(`${API_URL}/shop/retained/${itemId}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			if (res.ok) fetchRetained();
		} catch (e) {
			console.error('Failed to remove retained item:', e);
		}
	}

	function onDragStart(e: DragEvent, item: ShopItem) {
		draggingId = item.id;
		e.dataTransfer?.setData('text/plain', String(item.id));
		if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
	}

	function onDragEnd() {
		draggingId = null;
		dropHover = false;
	}

	function onDropZoneDragOver(e: DragEvent) {
		e.preventDefault();
		dropHover = true;
	}

	function onDropZoneDragLeave() {
		dropHover = false;
	}

	async function onDropZoneDrop(e: DragEvent) {
		e.preventDefault();
		dropHover = false;
		const idStr = e.dataTransfer?.getData('text/plain');
		if (!idStr) return;
		await retain(Number(idStr));
		draggingId = null;
	}

	function getProbabilityColor(prob: number): string {
		if (prob >= 70) return 'text-green-600';
		if (prob >= 40) return 'text-yellow-600';
		return 'text-red-600';
	}

	function getProbabilityBgColor(prob: number): string {
		if (prob >= 70) return 'bg-green-100';
		if (prob >= 40) return 'bg-yellow-100';
		return 'bg-red-100';
	}

	async function checkPendingOrders() {
		try {
			const response = await fetch(`${API_URL}/shop/orders/pending-address`, {
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				if (Array.isArray(data) && data.length > 0) {
					pendingOrders = data.map((o: { id: number; itemName: string }) => ({
						orderId: o.id,
						itemName: o.itemName
					}));
					const first = pendingOrders[0];
					winningOrderId = first.orderId;
					winningItemName = first.itemName;
				}
			}
		} catch (e) {
			console.error('Failed to check pending orders:', e);
		}
	}

	function handleTryLuck(orderId: number) {
		if (selectedItem) {
			winningItemName = selectedItem.name;
		}
		winningOrderId = orderId;
		selectedItem = null;
	}

	function handlePurchase(orderId: number) {
		if (selectedItem) {
			winningItemName = selectedItem.name;
		}
		winningOrderId = orderId;
		selectedItem = null;
	}

	function handleConsolation(orderId: number, rolled: number, needed: number) {
		consolationOrderId = orderId;
		consolationRolled = rolled;
		consolationNeeded = needed;
		selectedItem = null;
	}

	function handleAddressComplete() {
		fetchShopItems(true);
		fetchDaily();
		fetchRetained();
		winningOrderId = null;
		winningItemName = null;
		pendingOrders = pendingOrders.slice(1);
		if (pendingOrders.length > 0) {
			const next = pendingOrders[0];
			winningOrderId = next.orderId;
			winningItemName = next.itemName;
		}
	}

	onMount(async () => {
		await getUser();
		fetchShopItems();
		fetchDaily();
		fetchRetained();
		checkPendingOrders();
	});

	async function toggleHeart(itemId: number) {
		try {
			const response = await fetch(`${API_URL}/shop/items/${itemId}/heart`, {
				method: 'POST',
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				updateShopItemHeart(itemId, data.hearted, data.heartCount);
			}
		} catch (error) {
			console.error('Failed to toggle heart:', error);
		}
	}
</script>

<svelte:head>
	<title>shop - scraps</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-2 text-4xl font-bold md:text-5xl">{$t.nav.shop}</h1>
	<p class="mb-8 text-lg text-gray-600">{$t.shop.itemsUpForGrabs}</p>

	<!-- New items of the day -->
	{#if dailyLoading}
		<div class="py-12 text-center">
			<p class="text-gray-600">{$t.shop.loadingItems}</p>
		</div>
	{:else if !revealed}
		<button
			onclick={revealToday}
			out:fade={{ duration: 400 }}
			class="mb-12 flex w-full cursor-pointer flex-col items-center gap-3 rounded-3xl border-4 border-black bg-gradient-to-b from-indigo-50 to-white p-16 text-center transition-all hover:border-dashed"
		>
			<Sparkles size={36} />
			<h2 class="text-2xl font-bold">new items of the day</h2>
			<p class="text-gray-500">click to reveal today's 5 picks</p>
		</button>
	{:else}
		<div in:fade={{ duration: 400 }}>
			<h2 class="mb-1 flex items-center gap-2 text-2xl font-bold"><Sparkles size={22} /> today's picks</h2>
			<p class="mb-4 text-sm text-gray-600">
				Drag one down into <strong>your shop</strong> to keep it forever, even after today.
			</p>
			<div class="mb-12 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
				{#each dailyItems as item (item.id)}
					{@const rollCost = getItemRollCost(item)}
					{@const alreadyRetained = retainedItems.some((r) => r.id === item.id)}
					<div
						role="listitem"
						draggable={!alreadyRetained}
						ondragstart={(e) => onDragStart(e, item)}
						ondragend={onDragEnd}
						class="relative overflow-hidden rounded-2xl border-4 border-black bg-yellow-50 transition-all {alreadyRetained
							? 'opacity-50'
							: 'cursor-grab active:cursor-grabbing'} {draggingId === item.id ? 'opacity-30' : ''}"
					>
						<button
							onclick={() => (selectedItem = item)}
							class="w-full cursor-pointer p-5 text-left hover:opacity-90"
						>
							<div class="relative">
								<img src={item.image} alt={item.name} class="mb-4 h-40 w-full object-contain" />
								<span
									class="absolute top-0 right-0 rounded-full px-2 py-1 text-xs font-bold {getProbabilityBgColor(
										item.effectiveProbability
									)} {getProbabilityColor(item.effectiveProbability)}"
								>
									{item.effectiveProbability.toFixed(0)}% {$t.shop.chance}
								</span>
							</div>
							<h3 class="mb-1 truncate text-2xl font-bold">{item.name}</h3>
							<p class="mb-3 line-clamp-2 text-sm text-gray-600">{item.description}</p>
							<div class="flex items-end justify-between">
								<div>
									<span class="flex items-center gap-1 text-xl font-bold"
										><Spool size={20} />{rollCost}</span
									>
									<span class="mt-1 flex items-center gap-1 text-xs text-gray-500"
										><Clock size={14} />~{estimateHours(rollCost)}h · {item.count} {$t.shop.left}</span
									>
								</div>
								<HeartButton
									count={item.heartCount}
									hearted={item.userHearted}
									onclick={(e) => {
										e.stopPropagation();
										toggleHeart(item.id);
									}}
								/>
							</div>
						</button>
						{#if !alreadyRetained}
							<div
								class="flex items-center justify-center gap-1 border-t-2 border-black py-2 text-xs font-bold text-gray-500"
							>
								<GripVertical size={14} /> drag to keep forever
							</div>
						{:else}
							<div
								class="flex items-center justify-center gap-1 border-t-2 border-black bg-green-100 py-2 text-xs font-bold text-green-700"
							>
								<Bookmark size={14} /> already in your shop
							</div>
						{/if}
					</div>
				{/each}
			</div>

			<!-- Your permanent shop — drop target -->
			<h2 class="mb-1 flex items-center gap-2 text-2xl font-bold"><Bookmark size={22} /> your shop</h2>
			<p class="mb-4 text-sm text-gray-600">
				{retainedItems.length}/{retainedCap} slots used — items here stay yours forever, even after
				they rotate out.
			</p>
			<div
				ondragover={onDropZoneDragOver}
				ondragleave={onDropZoneDragLeave}
				ondrop={onDropZoneDrop}
				role="list"
				class="mb-12 min-h-40 rounded-2xl border-4 border-dashed p-4 transition-all {dropHover
					? 'border-black bg-indigo-50'
					: 'border-gray-300'}"
			>
				{#if retainedLoading}
					<p class="py-8 text-center text-gray-500">loading…</p>
				{:else if retainedItems.length === 0}
					<p class="py-8 text-center text-gray-400">
						drag an item here from today's picks to keep it forever
					</p>
				{:else}
					<div class="grid grid-cols-1 gap-6 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
						{#each retainedItems as item (item.id)}
							{@const rollCost = getItemRollCost(item)}
							<div
								class="relative overflow-hidden rounded-2xl border-4 border-green-500 {item.count === 0
									? 'opacity-50 grayscale'
									: ''}"
							>
								<button
									onclick={() => (selectedItem = item)}
									class="w-full cursor-pointer p-4 text-left hover:opacity-90"
								>
									<div class="relative">
										<img src={item.image} alt={item.name} class="mb-4 h-32 w-full object-contain" />
										<span
											class="absolute top-0 right-0 rounded-full px-2 py-1 text-xs font-bold {getProbabilityBgColor(
												item.effectiveProbability
											)} {getProbabilityColor(item.effectiveProbability)}"
										>
											{item.effectiveProbability.toFixed(0)}%
										</span>
									</div>
									<h3 class="mb-1 truncate text-xl font-bold">{item.name}</h3>
									<span class="flex items-center gap-1 text-lg font-bold"
										><Spool size={18} />{rollCost}</span
									>
									<span class="text-xs text-gray-500"
										>{item.count === 0 ? 'restocking' : `${item.count} ${$t.shop.left}`}</span
									>
								</button>
								<button
									onclick={() => unretain(item.id)}
									class="flex w-full cursor-pointer items-center justify-center gap-1 border-t-2 border-green-500 py-2 text-xs font-bold text-gray-500 hover:text-red-600"
								>
									<X size={14} /> remove from shop
								</button>
							</div>
						{/each}
					</div>
				{/if}
			</div>

			{#if notInRotation.length > 0}
				<h2 class="mb-4 text-2xl font-bold text-gray-400">not in today's rotation</h2>
				<div class="grid grid-cols-1 gap-6 opacity-50 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
					{#each notInRotation as item (item.id)}
						{@const rollCost = getItemRollCost(item)}
						<button
							onclick={() => (selectedItem = item)}
							class="relative cursor-pointer overflow-hidden rounded-2xl border-4 border-black p-4 text-left transition-all hover:border-dashed"
						>
							<img src={item.image} alt={item.name} class="mb-4 h-32 w-full object-contain" />
							<h3 class="mb-1 truncate text-xl font-bold">{item.name}</h3>
							<span class="flex items-center gap-1 text-lg font-bold"
								><Spool size={18} />{rollCost}</span
							>
						</button>
					{/each}
				</div>
			{/if}
		</div>
	{/if}
</div>

{#if selectedItem}
	<ShopItemModal
		item={selectedItem}
		onClose={() => (selectedItem = null)}
		onTryLuck={handleTryLuck}
		onConsolation={handleConsolation}
		onPurchase={handlePurchase}
	/>
{/if}

{#if winningOrderId && winningItemName}
	<AddressSelectModal
		orderId={winningOrderId}
		itemName={winningItemName}
		onClose={() => {
			winningOrderId = null;
			winningItemName = null;
		}}
		onComplete={handleAddressComplete}
	/>
{/if}

{#if consolationOrderId}
	<AddressSelectModal
		orderId={consolationOrderId}
		itemName={$t.shop.consolationScrapPaper}
		onClose={() => {
			consolationOrderId = null;
			consolationRolled = null;
			consolationNeeded = null;
		}}
		onComplete={() => {
			consolationOrderId = null;
			consolationRolled = null;
			consolationNeeded = null;
		}}
	>
		{#snippet header()}
			<div class="mb-4 rounded-xl border-2 border-yellow-400 bg-yellow-50 p-4">
				<p class="font-bold text-yellow-800">{$t.shop.betterLuckNextTime}</p>
				<p class="mt-1 text-sm text-yellow-700">
					{$t.shop.youRolledButNeeded
						.replace('{rolled}', String(consolationRolled))
						.replace('{needed}', String(consolationNeeded))}
				</p>
				<p class="mt-2 text-sm text-yellow-700">
					{$t.shop.consolationMessage}
				</p>
			</div>
		{/snippet}
	</AddressSelectModal>
{/if}

<a
	href="/orders"
	class="fixed right-4 bottom-6 z-40 flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 sm:right-6 sm:px-6 sm:py-3"
>
	<PackageCheck size={20} />
	<span class="hidden sm:inline">{$t.shop.myOrders}</span>
</a>
