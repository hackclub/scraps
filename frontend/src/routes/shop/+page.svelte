<script lang="ts">
	import { onMount } from 'svelte';
	import { fade } from 'svelte/transition';
	import ShopItemModal from '$lib/components/ShopItemModal.svelte';
	import AddressSelectModal from '$lib/components/AddressSelectModal.svelte';
	import GachaponPull from '$lib/components/GachaponPull.svelte';
	import GachaponDetailModal from '$lib/components/GachaponDetailModal.svelte';
	import { API_URL } from '$lib/config';
	import { getUser } from '$lib/auth-client';
	import {
		Spool,
		PackageCheck,
		Sparkles,
		Bookmark,
		GripVertical,
		X,
		PackageOpen,
		HelpCircle
	} from '@lucide/svelte';
	import { shopLoading, fetchShopItems, showToast, type ShopItem } from '$lib/stores';
	import { t } from '$lib/i18n';
	import { isInfiniteStock } from '$lib/utils';

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
		items: { id: number; name: string; image: string; count: number; pullChance: number }[];
	}

	const domeColors = ['#f87171', '#fbbf24', '#60a5fa', '#c084fc', '#4ade80'];

	let gachapons = $state<Gachapon[]>([]);
	let gachaponsLoading = $state(true);
	let pullingGachaponId = $state<number | null>(null);
	let twitchingGachaponId = $state<number | null>(null);
	let detailGachapon = $state<Gachapon | null>(null);

	function domeFor(g: Gachapon): string {
		const i = gachapons.findIndex((x) => x.id === g.id);
		return domeColors[(i < 0 ? 0 : i) % domeColors.length];
	}

	function startPull(gachapon: Gachapon) {
		if (pullingGachaponId === gachapon.id || twitchingGachaponId === gachapon.id || pullReveal) {
			return;
		}
		twitchingGachaponId = gachapon.id;
		setTimeout(() => {
			twitchingGachaponId = null;
			pullGachapon(gachapon);
		}, 380);
	}
	let pullReveal = $state<{
		orderId: number;
		itemName: string;
		itemImage: string | null;
		gachaponName: string;
	} | null>(null);

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
				pullReveal = {
					orderId: data.order.id,
					itemName: data.order.itemName,
					itemImage: data.order.itemImage ?? null,
					gachaponName: gachapon.name
				};
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

	function finishPullReveal() {
		if (!pullReveal) return;
		winningItemName = pullReveal.itemName;
		winningOrderId = pullReveal.orderId;
		pullReveal = null;
		detailGachapon = null;
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
				showToast('moved to shop!', 'success');
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

	async function refreshPendingAddress() {
		try {
			const response = await fetch(`${API_URL}/shop/orders/pending-address`, {
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				pendingOrders = Array.isArray(data)
					? data.map((o: { id: number; itemName: string }) => ({
							orderId: o.id,
							itemName: o.itemName
						}))
					: [];
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
		refreshPendingAddress();
	}

	onMount(async () => {
		await getUser();
		fetchShopItems();
		fetchDaily();
		fetchRetained();
		fetchGachapons();
		refreshPendingAddress();
	});
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
			<section class="mb-12 rounded-2xl border border-gray-300 p-5 sm:p-6">
			<h2 class="mb-1 flex items-center gap-2 text-2xl font-bold">
				<Sparkles size={22} /> today's picks
			</h2>
			<p class="mb-4 text-sm text-gray-600">
				Drag one down into <strong>your shop</strong> to keep it forever, even after today | or drag one
				back up here to let it go.
			</p>
			{#if visibleDailyItems.length === 0}
				<p
					ondragover={onDailyZoneDragOver}
					ondragleave={onDailyZoneDragLeave}
					ondrop={onDailyZoneDrop}
					role="list"
					class="mb-4 rounded-2xl border-4 border-dashed p-8 text-center transition-all {dailyDropHover
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
				class="grid grid-cols-5 gap-2 rounded-2xl border-4 p-2 transition-all sm:gap-3 {dailyDropHover
					? 'border-dashed border-black bg-indigo-50'
					: 'border-transparent'}"
			>
				{#each visibleDailyItems as item (item.id)}
					<div
						role="listitem"
						draggable={true}
						ondragstart={(e) => onDragStart(e, item)}
						ondragend={onDragEnd}
						class="relative cursor-grab overflow-hidden rounded-xl border-4 border-black bg-white transition-all active:cursor-grabbing {draggingId ===
						item.id
							? 'opacity-30'
							: ''}"
					>
						<button
							onclick={() => (selectedItem = item)}
							class="w-full cursor-pointer p-2 text-left hover:opacity-90"
						>
							<div class="relative">
								<img
									src={item.image}
									alt={item.name}
									class="mb-1 h-14 w-full object-contain sm:h-20"
								/>
								<span
									class="absolute top-0 right-0 rounded-full bg-black px-1.5 py-0.5 text-[10px] font-bold text-white"
								>
									{item.effectiveProbability.toFixed(0)}%
								</span>
							</div>
							<h3 class="truncate text-xs font-bold sm:text-sm">{item.name}</h3>
							<span class="flex items-center gap-1 text-xs font-bold sm:text-sm"
								><Spool size={12} />{getItemRollCost(item)}</span
							>
						</button>
						<div
							class="flex items-center justify-center gap-1 border-t-2 border-black py-1 text-[10px] font-bold text-gray-500"
							title="drag to keep forever"
						>
							<GripVertical size={12} />
						</div>
					</div>
				{/each}
			</div>
			</section>

			<!-- Your permanent shop: drop target -->
			<h2 class="mb-1 flex items-center gap-2 text-2xl font-bold">
				<Bookmark size={22} /> your shop
			</h2>
			<p class="mb-4 text-sm text-gray-600">
				{retainedItems.length}/{retainedCap} slots used: items here stay yours forever, even after they
				rotate out.
			</p>
			<div
				ondragover={onDropZoneDragOver}
				ondragleave={onDropZoneDragLeave}
				ondrop={onDropZoneDrop}
				role="list"
				class="mb-12 min-h-40 rounded-2xl border-4 p-4 transition-all {dropHover
					? 'border-dashed border-black bg-indigo-50'
					: retainedItems.length > 0
						? 'border-solid border-black'
						: 'border-dashed border-gray-300'}"
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
								class="relative cursor-grab overflow-hidden rounded-2xl border-4 border-black transition-all active:cursor-grabbing {item.count ===
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
											class="absolute top-0 right-0 rounded-full bg-black px-2 py-1 text-xs font-bold text-white"
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
									class="flex w-full cursor-pointer items-center justify-center gap-1 border-t-2 border-black py-2 text-xs font-bold text-gray-500 hover:text-red-600"
								>
									<X size={14} /> remove from shop
								</button>
							</div>
						{/each}
					</div>
				{/if}
			</div>
		</div>
	{/if}

	<h2 class="mt-12 mb-1 flex items-center gap-2 text-2xl font-bold">
		<PackageOpen size={22} /> gachapons
	</h2>
	<p class="mb-4 text-sm text-gray-600">
		guaranteed to get one item from the pool: costs a bit more than buying it straight, since
		there's no risk.
	</p>
	{#if gachaponsLoading}
		<div class="py-8 text-center text-gray-500">loading…</div>
	{:else if gachapons.length === 0}
		<p class="rounded-2xl border-4 border-dashed border-gray-300 p-8 text-center text-gray-400">
			no gachapons right now
		</p>
	{:else}
		<div class="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-3">
			{#each gachapons as gachapon, gi (gachapon.id)}
				{@const inStock = gachapon.items.filter((i) => i.count !== 0)}
				{@const dome = domeColors[gi % domeColors.length]}
				<div
					class="gachapon-machine"
					class:twitch={twitchingGachaponId === gachapon.id}
					style="--dome:{dome}"
				>
					<button
						type="button"
						onclick={() => (detailGachapon = gachapon)}
						class="gachapon-globe cursor-pointer"
						title="see what's inside"
					>
						<div class="gachapon-globe-inner">
							{#if gachapon.image}
								<img class="gachapon-hero" src={gachapon.image} alt={gachapon.name} />
							{:else}
								<div class="gachapon-hero-fallback">
									<HelpCircle size={72} strokeWidth={2.5} />
								</div>
							{/if}
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
								onclick={() => startPull(gachapon)}
								disabled={pullingGachaponId === gachapon.id ||
									twitchingGachaponId === gachapon.id ||
									inStock.length === 0 ||
									!!pullReveal}
								class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
							>
								<Spool size={18} />
								{inStock.length === 0
									? 'sold out'
									: pullingGachaponId === gachapon.id || twitchingGachaponId === gachapon.id
										? 'pulling…'
										: `pull for ${gachapon.price}`}
							</button>
							<span class="gachapon-knob" aria-hidden="true"></span>
						</div>
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

{#if detailGachapon && !pullReveal}
	<GachaponDetailModal
		gachapon={detailGachapon}
		domeColor={domeFor(detailGachapon)}
		pulling={pullingGachaponId === detailGachapon.id}
		onPull={() => detailGachapon && pullGachapon(detailGachapon)}
		onClose={() => (detailGachapon = null)}
	/>
{/if}

{#if pullReveal}
	<GachaponPull
		itemName={pullReveal.itemName}
		itemImage={pullReveal.itemImage}
		gachaponName={pullReveal.gachaponName}
		onDone={finishPullReveal}
	/>
{/if}

{#if winningOrderId && winningItemName && !pullReveal}
	<AddressSelectModal
		orderId={winningOrderId}
		itemName={winningItemName}
		onClose={() => {
			winningOrderId = null;
			winningItemName = null;
			refreshPendingAddress();
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
	{#if pendingOrders.length > 0}
		<span
			class="absolute -top-2 -right-2 flex h-6 min-w-6 items-center justify-center rounded-full border-2 border-black bg-white px-1 text-xs font-bold text-black"
			title="{pendingOrders.length} order{pendingOrders.length === 1
				? ''
				: 's'} still need a shipping address"
		>
			{pendingOrders.length}
		</span>
	{/if}
</a>

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

	.gachapon-hero,
	.gachapon-hero-fallback {
		position: absolute;
		inset: 12%;
		display: flex;
		align-items: center;
		justify-content: center;
		object-fit: contain;
		filter: drop-shadow(0 3px 5px rgba(0, 0, 0, 0.22));
	}

	.gachapon-hero-fallback {
		color: color-mix(in srgb, var(--dome) 55%, #000);
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
