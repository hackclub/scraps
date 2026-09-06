<script lang="ts">
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';
	import HeartButton from '$lib/components/HeartButton.svelte';
	import ShopItemModal from '$lib/components/ShopItemModal.svelte';
	import AddressSelectModal from '$lib/components/AddressSelectModal.svelte';
	import { API_URL } from '$lib/config';
	import { getUser } from '$lib/auth-client';
	import {
		Spool,
		PackageCheck,
		Clock,
		Sparkles,
		Bookmark,
		GripVertical,
		X,
		PackageOpen
	} from '@lucide/svelte';
	import {
		shopItemsStore,
		shopLoading,
		fetchShopItems,
		updateShopItemHeart,
		showToast,
		type ShopItem
	} from '$lib/stores';
	import { t } from '$lib/i18n';
	import { isInfiniteStock, stockLabel } from '$lib/utils';

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

	interface Gachapon {
		id: number;
		name: string;
		description: string | null;
		image: string | null;
		price: number;
		items: { id: number; name: string; image: string; count: number }[];
	}

	let gachapons = $state<Gachapon[]>([]);
	let gachaponsLoading = $state(true);
	let pullingGachaponId = $state<number | null>(null);

	async function fetchGachapons() {
		gachaponsLoading = true;
		try {
			const res = await fetch(`${API_URL}/shop/gachapons`, { credentials: 'include' });
			if (res.ok) gachapons = await res.json();
		} catch (e) {
			console.error('Failed to load gachapons:', e);
		} finally {
			gachaponsLoading = false;
		}
	}

	async function pullGachapon(gachapon: Gachapon) {
		pullingGachaponId = gachapon.id;
		try {
			const res = await fetch(`${API_URL}/shop/gachapons/${gachapon.id}/purchase`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await res.json();
			if (res.ok && data.success) {
				winningItemName = data.order.itemName;
				winningOrderId = data.order.id;
			} else {
				showToast(data.error || 'could not pull that gachapon', 'error');
			}
		} catch (e) {
			console.error('Failed to pull gachapon:', e);
			showToast('could not pull that gachapon', 'error');
		} finally {
			pullingGachaponId = null;
		}
	}

	let dailyDate = $state('');
	let dailyItems = $state<ShopItem[]>([]);
	let dailyLoading = $state(true);
	let revealed = $state(false);

	let retainedItems = $state<ShopItem[]>([]);
	let retainedCap = $state(2);
	let retainedLoading = $state(true);
	let draggingId = $state<number | null>(null);
	let dropHover = $state(false);

	let visibleDailyItems = $derived(
		dailyItems.filter((d) => !retainedItems.some((r) => r.id === d.id))
	);

	let notInRotation = $derived(
		$shopItemsStore.filter(
			(i) =>
				i.count !== 0 &&
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

	let dailyDropHover = $state(false);

	function onDailyZoneDragOver(e: DragEvent) {
		e.preventDefault();
		dailyDropHover = true;
	}

	function onDailyZoneDragLeave() {
		dailyDropHover = false;
	}

	async function onDailyZoneDrop(e: DragEvent) {
		e.preventDefault();
		dailyDropHover = false;
		const idStr = e.dataTransfer?.getData('text/plain');
		if (!idStr) return;
		const itemId = Number(idStr);
		if (retainedItems.some((i) => i.id === itemId)) {
			await unretain(itemId);
		}
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
		fetchGachapons();
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
		fetchGachapons();
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
				Drag one down into <strong>your shop</strong> to keep it forever, even after today — or drag
				one back up here to let it go.
			</p>
			{#if visibleDailyItems.length === 0}
				<p
					ondragover={onDailyZoneDragOver}
					ondragleave={onDailyZoneDragLeave}
					ondrop={onDailyZoneDrop}
					role="list"
					class="mb-12 rounded-2xl border-4 border-dashed p-8 text-center transition-all {dailyDropHover
						? 'border-black bg-indigo-50 text-gray-600'
						: 'border-gray-300 text-gray-400'}"
				>
					you've already kept everything from today's picks
				</p>
			{/if}
			<div
				ondragover={onDailyZoneDragOver}
				ondragleave={onDailyZoneDragLeave}
				ondrop={onDailyZoneDrop}
				role="list"
				class="mb-12 grid grid-cols-1 gap-6 rounded-2xl border-4 p-2 transition-all sm:grid-cols-2 lg:grid-cols-3 {dailyDropHover
					? 'border-dashed border-black bg-indigo-50'
					: 'border-transparent'}"
			>
				{#each visibleDailyItems as item (item.id)}
					{@const rollCost = getItemRollCost(item)}
					<div
						role="listitem"
						draggable={true}
						ondragstart={(e) => onDragStart(e, item)}
						ondragend={onDragEnd}
						class="relative overflow-hidden rounded-2xl border-4 border-black bg-yellow-50 transition-all cursor-grab active:cursor-grabbing {draggingId ===
						item.id
							? 'opacity-30'
							: ''}"
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
							{#if item.sizeVariants && item.sizeVariants.length > 0}
								<div class="mb-2 flex flex-wrap gap-1">
									{#each item.sizeVariants as variant (variant.name)}
										<span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-bold"
											>{variant.name} · {variant.count}</span
										>
									{/each}
								</div>
							{/if}
							<div class="flex items-end justify-between">
								<div>
									<span class="flex items-center gap-1 text-xl font-bold"
										><Spool size={20} />{rollCost}</span
									>
									<span class="mt-1 flex items-center gap-1 text-xs text-gray-500"
										><Clock size={14} />~{estimateHours(rollCost)}h · {stockLabel(item.count)}
										{isInfiniteStock(item.count) ? '' : $t.shop.left}</span
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
						<div
							class="flex items-center justify-center gap-1 border-t-2 border-black py-2 text-xs font-bold text-gray-500"
						>
							<GripVertical size={14} /> drag to keep forever
						</div>
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
								role="listitem"
								draggable={true}
								ondragstart={(e) => onDragStart(e, item)}
								ondragend={onDragEnd}
								class="relative overflow-hidden rounded-2xl border-4 border-green-500 transition-all cursor-grab active:cursor-grabbing {item.count ===
								0
									? 'opacity-50 grayscale'
									: ''} {draggingId === item.id ? 'opacity-30' : ''}"
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
										>{item.count === 0
											? 'restocking'
											: isInfiniteStock(item.count)
												? '∞'
												: `${item.count} ${$t.shop.left}`}</span
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

	<h2 class="mt-12 mb-1 flex items-center gap-2 text-2xl font-bold">
		<PackageOpen size={22} /> gachapons
	</h2>
	<p class="mb-4 text-sm text-gray-600">
		guaranteed to get one item from the pool — costs a bit more than buying it straight, since
		there's no risk.
	</p>
	{#if gachaponsLoading}
		<div class="py-8 text-center text-gray-500">loading…</div>
	{:else if gachapons.length === 0}
		<p class="rounded-2xl border-4 border-dashed border-gray-300 p-8 text-center text-gray-400">
			no gachapons right now
		</p>
	{:else}
		<div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
			{#each gachapons as gachapon (gachapon.id)}
				{@const inStock = gachapon.items.filter((i) => i.count !== 0)}
				<div class="overflow-hidden rounded-2xl border-4 border-black bg-purple-50">
					{#if gachapon.image}
						<img src={gachapon.image} alt={gachapon.name} class="h-32 w-full object-cover" />
					{:else}
						<div class="flex h-32 w-full items-center justify-center bg-purple-100">
							<PackageOpen size={32} class="text-purple-300" />
						</div>
					{/if}
					<div class="p-5">
						<h3 class="mb-1 text-xl font-bold">{gachapon.name}</h3>
						{#if gachapon.description}
							<p class="mb-3 text-sm text-gray-600">{gachapon.description}</p>
						{/if}
						<div class="mb-3 flex flex-wrap gap-1">
							{#each gachapon.items as item (item.id)}
								<img
									src={item.image}
									alt={item.name}
									title={item.name}
									class="h-10 w-10 rounded-lg border-2 border-black object-cover {item.count === 0
										? 'opacity-30 grayscale'
										: ''}"
								/>
							{/each}
						</div>
						<p class="mb-3 text-xs text-gray-500">
							guaranteed one of {gachapon.items.length} items — {inStock.length} in stock
						</p>
						<button
							onclick={() => pullGachapon(gachapon)}
							disabled={pullingGachaponId === gachapon.id || inStock.length === 0}
							class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
						>
							<Spool size={18} />
							{inStock.length === 0
								? 'sold out'
								: pullingGachaponId === gachapon.id
									? 'pulling…'
									: `pull for ${gachapon.price}`}
						</button>
					</div>
				</div>
			{/each}
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
