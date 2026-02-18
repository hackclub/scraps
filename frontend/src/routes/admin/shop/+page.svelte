<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { Plus, Pencil, Trash2, X, Spool, Package } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';

	interface ShopItem {
		id: number;
		name: string;
		image: string;
		description: string;
		price: number;
		category: string;
		count: number;
		baseProbability: number;
		baseUpgradeCost: number;
		costMultiplier: number;
		boostAmount: number;
		createdAt: string;
		updatedAt: string;
	}

	interface LootboxItem {
		lootboxId: number;
		shopItemId: number;
		percentage: number;
		itemName: string;
		itemImage: string;
		itemPrice: number;
		itemCount: number;
	}

	interface Lootbox {
		id: number;
		name: string;
		image: string;
		description: string;
		price: number;
		category: string;
		items: LootboxItem[];
		createdAt: string;
		updatedAt: string;
	}

	interface User {
		id: number;
		role: string;
	}

	let user = $state<User | null>(null);
	let items = $state<ShopItem[]>([]);
	let lootboxes = $state<Lootbox[]>([]);
	let loading = $state(true);
	let saving = $state(false);

	// Item modal state
	let showModal = $state(false);
	let editingItem = $state<ShopItem | null>(null);

	let formName = $state('');
	let formImage = $state('');
	let formDescription = $state('');
	let formPrice = $state(0);
	let formCategory = $state('');
	let formCount = $state(0);
	let formBaseProbability = $state(50);
	let formBaseUpgradeCost = $state(10);
	let formCostMultiplier = $state(101);
	let formBoostAmount = $state(1);
	let formMonetaryValue = $state(0);
	let formError = $state<string | null>(null);
	let errorModal = $state<string | null>(null);

	// Lootbox modal state
	let showLootboxModal = $state(false);
	let editingLootbox = $state<Lootbox | null>(null);
	let lbName = $state('');
	let lbImage = $state('');
	let lbDescription = $state('');
	let lbPrice = $state(0);
	let lbCategory = $state('');
	let lbSelectedItems = $state<{ shopItemId: number; percentage: number }[]>([]);
	let lbError = $state<string | null>(null);
	let lbSaving = $state(false);

	let deleteConfirmId = $state<number | null>(null);
	let deleteLootboxConfirmId = $state<number | null>(null);

	const PHI = (1 + Math.sqrt(5)) / 2;
	const SCRAPS_PER_HOUR = PHI * 10;
	const DOLLARS_PER_HOUR = 5;
	const SCRAPS_PER_DOLLAR = SCRAPS_PER_HOUR / DOLLARS_PER_HOUR;

	let lbPercentageSum = $derived(lbSelectedItems.reduce((sum, i) => sum + i.percentage, 0));

	function calculatePricing(monetaryValue: number, stockCount: number) {
		const price = Math.round(monetaryValue * SCRAPS_PER_DOLLAR);

		const priceRarityFactor = Math.max(0, 1 - monetaryValue / 100);
		const stockRarityFactor = Math.min(1, stockCount / 20);
		const baseProbability = Math.max(
			5,
			Math.min(80, Math.round((priceRarityFactor * 0.4 + stockRarityFactor * 0.6) * 80))
		);

		const rollCost = Math.max(1, Math.round(price * (baseProbability / 100)));
		const upgradeBudget = Math.max(0, price * 1.5 - rollCost);
		const probabilityGap = 100 - baseProbability;

		const targetUpgrades = Math.max(5, Math.min(20, Math.ceil(monetaryValue / 5)));
		const boostAmount = Math.max(1, Math.round(probabilityGap / targetUpgrades));
		const actualUpgrades = Math.ceil(probabilityGap / boostAmount);

		const costMultiplier = 110;
		const multiplierDecimal = costMultiplier / 100;

		let baseUpgradeCost: number;
		if (actualUpgrades <= 0 || upgradeBudget <= 0) {
			baseUpgradeCost = Math.round(price * 0.05) || 1;
		} else {
			const seriesSum = (Math.pow(multiplierDecimal, actualUpgrades) - 1) / (multiplierDecimal - 1);
			baseUpgradeCost = Math.max(1, Math.round(upgradeBudget / seriesSum));
		}

		return { price, baseProbability, baseUpgradeCost, costMultiplier, boostAmount };
	}

	function recalculatePricing() {
		const pricing = calculatePricing(formMonetaryValue, formCount);
		formPrice = pricing.price;
		formBaseProbability = pricing.baseProbability;
		formBaseUpgradeCost = pricing.baseUpgradeCost;
		formCostMultiplier = pricing.costMultiplier;
		formBoostAmount = pricing.boostAmount;
	}

	function updateFromMonetary(value: number) {
		formMonetaryValue = value;
		recalculatePricing();
	}

	function updateFromStock(value: number) {
		formCount = value;
		recalculatePricing();
	}

	onMount(async () => {
		user = await getUser();
		if (!user || user.role !== 'admin') {
			goto('/dashboard');
			return;
		}

		await Promise.all([fetchItems(), fetchLootboxes()]);
	});

	async function fetchItems() {
		loading = true;
		try {
			const response = await fetch(`${API_URL}/admin/shop/items`, {
				credentials: 'include'
			});
			if (response.ok) {
				items = await response.json();
			}
		} catch (e) {
			console.error('Failed to fetch items:', e);
		} finally {
			loading = false;
		}
	}

	async function fetchLootboxes() {
		try {
			const response = await fetch(`${API_URL}/admin/lootboxes`, {
				credentials: 'include'
			});
			if (response.ok) {
				lootboxes = await response.json();
			}
		} catch (e) {
			console.error('Failed to fetch lootboxes:', e);
		}
	}

	// Item modal functions
	function openCreateModal() {
		editingItem = null;
		formName = '';
		formImage = '';
		formDescription = '';
		formPrice = 0;
		formMonetaryValue = 0;
		formCategory = '';
		formCount = 0;
		formBaseProbability = 50;
		formBaseUpgradeCost = 10;
		formCostMultiplier = 101;
		formBoostAmount = 1;
		formError = null;
		showModal = true;
	}

	function openEditModal(item: ShopItem) {
		editingItem = item;
		formName = item.name;
		formImage = item.image;
		formDescription = item.description;
		formPrice = item.price;
		formMonetaryValue = item.price / SCRAPS_PER_DOLLAR;
		formCategory = item.category;
		formCount = item.count;
		formBaseProbability = item.baseProbability;
		formBaseUpgradeCost = item.baseUpgradeCost;
		formCostMultiplier = item.costMultiplier;
		formBoostAmount = item.boostAmount ?? 1;
		formError = null;
		showModal = true;
	}

	function closeModal() {
		showModal = false;
		editingItem = null;
	}

	async function handleSubmit() {
		if (!formName.trim() || !formImage.trim() || !formDescription.trim() || !formCategory.trim()) {
			formError = 'All fields are required';
			return;
		}

		saving = true;
		formError = null;

		try {
			const url = editingItem
				? `${API_URL}/admin/shop/items/${editingItem.id}`
				: `${API_URL}/admin/shop/items`;

			const response = await fetch(url, {
				method: editingItem ? 'PUT' : 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({
					name: formName,
					image: formImage,
					description: formDescription,
					price: formPrice,
					category: formCategory,
					count: formCount,
					baseProbability: formBaseProbability,
					baseUpgradeCost: formBaseUpgradeCost,
					costMultiplier: formCostMultiplier,
					boostAmount: formBoostAmount
				})
			});

			if (response.ok) {
				closeModal();
				await fetchItems();
			} else {
				const data = await response.json();
				formError = data.error || 'Failed to save';
			}
		} catch (e) {
			formError = 'Failed to save item';
		} finally {
			saving = false;
		}
	}

	function requestDelete(id: number) {
		deleteConfirmId = id;
	}

	async function confirmDelete() {
		if (!deleteConfirmId) return;

		try {
			const response = await fetch(`${API_URL}/admin/shop/items/${deleteConfirmId}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			if (response.ok) {
				await fetchItems();
			} else {
				const data = await response.json();
				errorModal = data.error || 'Failed to delete item';
			}
		} catch (e) {
			console.error('Failed to delete:', e);
			errorModal = 'Failed to delete item';
		} finally {
			deleteConfirmId = null;
		}
	}

	// Lootbox modal functions
	function openCreateLootboxModal() {
		editingLootbox = null;
		lbName = '';
		lbImage = '';
		lbDescription = '';
		lbPrice = 0;
		lbCategory = '';
		lbSelectedItems = [];
		lbError = null;
		showLootboxModal = true;
	}

	function openEditLootboxModal(lb: Lootbox) {
		editingLootbox = lb;
		lbName = lb.name;
		lbImage = lb.image;
		lbDescription = lb.description;
		lbPrice = lb.price;
		lbCategory = lb.category;
		lbSelectedItems = lb.items.map((i) => ({
			shopItemId: i.shopItemId,
			percentage: i.percentage
		}));
		lbError = null;
		showLootboxModal = true;
	}

	function closeLootboxModal() {
		showLootboxModal = false;
		editingLootbox = null;
	}

	function toggleLootboxItem(shopItemId: number) {
		const exists = lbSelectedItems.find((i) => i.shopItemId === shopItemId);
		if (exists) {
			lbSelectedItems = lbSelectedItems.filter((i) => i.shopItemId !== shopItemId);
		} else {
			lbSelectedItems = [...lbSelectedItems, { shopItemId, percentage: 0 }];
		}
	}

	function autoFillPercentages() {
		if (lbSelectedItems.length === 0) return;

		const selectedShopItems = lbSelectedItems.map((si) => {
			const item = items.find((i) => i.id === si.shopItemId);
			return { ...si, price: item?.price ?? 1 };
		});

		// Inversely proportional to price
		const weights = selectedShopItems.map((i) => 1 / Math.max(1, i.price));
		const totalWeight = weights.reduce((sum, w) => sum + w, 0);

		let percentages = weights.map((w) => Math.max(1, Math.round((w / totalWeight) * 100)));
		let total = percentages.reduce((sum, p) => sum + p, 0);

		// Adjust rounding: add/subtract from the largest item
		if (total !== 100) {
			const maxIdx = percentages.indexOf(Math.max(...percentages));
			percentages[maxIdx] += 100 - total;
		}

		lbSelectedItems = lbSelectedItems.map((si, idx) => ({
			...si,
			percentage: percentages[idx]
		}));
	}

	function updateLbItemPercentage(shopItemId: number, value: number) {
		lbSelectedItems = lbSelectedItems.map((i) =>
			i.shopItemId === shopItemId ? { ...i, percentage: value } : i
		);
	}

	async function handleLootboxSubmit() {
		if (!lbName.trim() || !lbImage.trim() || !lbDescription.trim() || !lbCategory.trim()) {
			lbError = 'All fields are required';
			return;
		}

		if (lbPrice < 1) {
			lbError = 'Price must be at least 1';
			return;
		}

		if (lbSelectedItems.length < 2) {
			lbError = $t.lootbox.atLeast2Items;
			return;
		}

		if (lbPercentageSum !== 100) {
			lbError = $t.lootbox.mustSumTo100;
			return;
		}

		lbSaving = true;
		lbError = null;

		try {
			const url = editingLootbox
				? `${API_URL}/admin/lootboxes/${editingLootbox.id}`
				: `${API_URL}/admin/lootboxes`;

			const response = await fetch(url, {
				method: editingLootbox ? 'PUT' : 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({
					name: lbName,
					image: lbImage,
					description: lbDescription,
					price: lbPrice,
					category: lbCategory,
					items: lbSelectedItems
				})
			});

			if (response.ok) {
				closeLootboxModal();
				await fetchLootboxes();
			} else {
				const data = await response.json();
				lbError = data.error || 'Failed to save lootbox';
			}
		} catch (e) {
			lbError = 'Failed to save lootbox';
		} finally {
			lbSaving = false;
		}
	}

	async function confirmDeleteLootbox() {
		if (!deleteLootboxConfirmId) return;

		try {
			const response = await fetch(`${API_URL}/admin/lootboxes/${deleteLootboxConfirmId}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			if (response.ok) {
				await fetchLootboxes();
			} else {
				const data = await response.json();
				errorModal = data.error || 'Failed to delete lootbox';
			}
		} catch (e) {
			console.error('Failed to delete lootbox:', e);
			errorModal = 'Failed to delete lootbox';
		} finally {
			deleteLootboxConfirmId = null;
		}
	}
</script>

<svelte:head>
	<title>{$t.nav.shop} - {$t.nav.admin} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-8 flex items-center justify-between">
		<div>
			<h1 class="mb-2 text-4xl font-bold md:text-5xl">{$t.nav.shop}</h1>
			<p class="text-lg text-gray-600">{$t.admin.manageShopItemsAndInventory}</p>
		</div>
		<div class="flex gap-2">
			<button
				onclick={openCreateLootboxModal}
				class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-6 py-3 font-bold transition-all duration-200 hover:border-dashed"
			>
				<Package size={20} />
				{$t.lootbox.createLootbox}
			</button>
			<button
				onclick={openCreateModal}
				class="flex cursor-pointer items-center gap-2 rounded-full bg-black px-6 py-3 font-bold text-white transition-all duration-200 hover:bg-gray-800"
			>
				<Plus size={20} />
				{$t.admin.addItem}
			</button>
		</div>
	</div>

	<div class="mb-8 rounded-2xl border-4 border-black p-4">
		<h3 class="mb-3 font-bold">scraps per hour reference</h3>
		<div class="grid grid-cols-4 gap-4 text-center text-sm">
			{#each [0.8, 1, 1.25, 1.5] as mult}
				<div class="rounded-lg bg-gray-100 p-3">
					<div class="mb-1 text-gray-500">{mult}x</div>
					<div class="flex items-center justify-center gap-1 font-bold">
						<Spool size={14} />
						{Math.round(SCRAPS_PER_HOUR * mult)}
					</div>
					<div class="text-xs text-gray-500">${(DOLLARS_PER_HOUR * mult).toFixed(2)}/hr</div>
				</div>
			{/each}
		</div>
	</div>

	<!-- Lootboxes Section -->
	{#if lootboxes.length > 0}
		<div class="mb-8">
			<h2 class="mb-4 text-2xl font-bold">{$t.lootbox.lootbox}s ({lootboxes.length})</h2>
			<div class="grid gap-4">
				{#each lootboxes as lb}
					<div class="flex items-center gap-4 rounded-2xl border-4 border-black bg-purple-50 p-4">
						<img
							src={lb.image}
							alt={lb.name}
							class="h-20 w-20 shrink-0 rounded-lg border-2 border-black object-cover"
						/>
						<div class="min-w-0 flex-1">
							<div class="flex items-center gap-2">
								<h3 class="text-xl font-bold">{lb.name}</h3>
								<span
									class="rounded-full border-2 border-purple-600 bg-purple-100 px-2 py-0.5 text-xs font-bold text-purple-700"
									>{$t.lootbox.badge}</span
								>
							</div>
							<p class="truncate text-sm text-gray-600">{lb.description}</p>
							<div class="mt-1 flex flex-wrap items-center gap-2 text-sm">
								<span class="flex items-center gap-1 font-bold"><Spool size={16} />{lb.price}</span>
								{#each lb.category
									.split(',')
									.map((c) => c.trim())
									.filter(Boolean) as cat}
									<span class="rounded-full bg-gray-100 px-2 py-0.5">{cat}</span>
								{/each}
								<span class="text-gray-500"
									>{lb.items.length} {$t.lootbox.items}</span
								>
								<span class="text-gray-500">•</span>
								<span class="text-xs text-gray-500">
									{#each lb.items as lbItem, i}
										{lbItem.itemName} ({lbItem.percentage}%){i < lb.items.length - 1 ? ', ' : ''}
									{/each}
								</span>
							</div>
						</div>
						<div class="flex shrink-0 gap-2">
							<button
								onclick={() => openEditLootboxModal(lb)}
								class="cursor-pointer rounded-lg border-4 border-black p-2 transition-all duration-200 hover:border-dashed"
							>
								<Pencil size={18} />
							</button>
							<button
								onclick={() => (deleteLootboxConfirmId = lb.id)}
								class="cursor-pointer rounded-lg border-4 border-red-600 p-2 text-red-600 transition-all duration-200 hover:bg-red-50"
							>
								<Trash2 size={18} />
							</button>
						</div>
					</div>
				{/each}
			</div>
		</div>
	{/if}

	<!-- Items Section -->
	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if items.length === 0}
		<div class="py-12 text-center text-gray-500">{$t.refinery.noItemsAvailable}</div>
	{:else}
		<h2 class="mb-4 text-2xl font-bold">{$t.lootbox.items} ({items.length})</h2>
		<div class="grid gap-4">
			{#each items as item}
				<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-4">
					<img
						src={item.image}
						alt={item.name}
						class="h-20 w-20 shrink-0 rounded-lg border-2 border-black object-cover"
					/>
					<div class="min-w-0 flex-1">
						<h3 class="text-xl font-bold">{item.name}</h3>
						<p class="truncate text-sm text-gray-600">{item.description}</p>
						<div class="mt-1 flex flex-wrap items-center gap-2 text-sm">
							<span class="font-bold">${(item.price / SCRAPS_PER_DOLLAR).toFixed(2)}</span>
							<span class="text-gray-500">•</span>
							<span class="flex items-center gap-1 font-bold"><Spool size={16} />{item.price}</span>
							{#each item.category
								.split(',')
								.map((c) => c.trim())
								.filter(Boolean) as cat}
								<span class="rounded-full bg-gray-100 px-2 py-0.5">{cat}</span>
							{/each}
							<span class="text-gray-500">{item.count} in stock</span>
							<span class="text-gray-500">•</span>
							<span class="text-gray-500">{item.baseProbability}%</span>
							<span class="text-gray-500">•</span>
							<span class="text-gray-500">+{item.boostAmount ?? 1}%/upgrade</span>
							<span class="text-gray-500">•</span>
							<span class="text-gray-500">~{(item.price / SCRAPS_PER_HOUR).toFixed(1)} hrs</span>
						</div>
					</div>
					<div class="flex shrink-0 gap-2">
						<button
							onclick={() => openEditModal(item)}
							class="cursor-pointer rounded-lg border-4 border-black p-2 transition-all duration-200 hover:border-dashed"
						>
							<Pencil size={18} />
						</button>
						<button
							onclick={() => requestDelete(item.id)}
							class="cursor-pointer rounded-lg border-4 border-red-600 p-2 text-red-600 transition-all duration-200 hover:bg-red-50"
						>
							<Trash2 size={18} />
						</button>
					</div>
				</div>
			{/each}
		</div>
	{/if}
</div>

<!-- Item Create/Edit Modal -->
{#if showModal}
	<div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
		<div
			class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border-4 border-black bg-white p-6"
		>
			<div class="mb-6 flex items-center justify-between">
				<h2 class="text-2xl font-bold">{editingItem ? $t.admin.editItem : $t.admin.addItem}</h2>
				<button
					onclick={closeModal}
					class="cursor-pointer rounded-lg p-2 transition-colors hover:bg-gray-100"
				>
					<X size={20} />
				</button>
			</div>

			{#if formError}
				<div class="mb-4 rounded-lg border-2 border-red-600 bg-red-50 p-3 text-sm text-red-600">
					{formError}
				</div>
			{/if}

			<div class="space-y-4">
				<div>
					<label for="name" class="mb-1 block text-sm font-bold">name</label>
					<input
						id="name"
						type="text"
						bind:value={formName}
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
				</div>

				<div>
					<label for="image" class="mb-1 block text-sm font-bold">image URL</label>
					<input
						id="image"
						type="text"
						bind:value={formImage}
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
				</div>

				<div>
					<label for="description" class="mb-1 block text-sm font-bold">description</label>
					<textarea
						id="description"
						bind:value={formDescription}
						rows="3"
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
				</div>

				<div>
					<label for="monetaryValue" class="mb-1 block text-sm font-bold">value ($)</label>
					<input
						id="monetaryValue"
						type="number"
						value={formMonetaryValue}
						oninput={(e) => updateFromMonetary(parseFloat(e.currentTarget.value) || 0)}
						min="0"
						step="0.01"
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
					<p class="mt-1 text-xs text-gray-500">
						= {formPrice} scraps · {formBaseProbability}% base · +{formBoostAmount}%/upgrade · ~{(
							formPrice / SCRAPS_PER_HOUR
						).toFixed(1)} hrs to earn
					</p>
					{#if formPrice > 0}
						{@const rollCost = Math.max(1, Math.round(formPrice * (formBaseProbability / 100)))}
						{@const probabilityGap = 100 - formBaseProbability}
						{@const upgradesNeeded = Math.ceil(probabilityGap / formBoostAmount)}
						{@const multiplierDecimal = formCostMultiplier / 100}
						{@const totalUpgradeCost =
							formBaseUpgradeCost *
							((Math.pow(multiplierDecimal, upgradesNeeded) - 1) / (multiplierDecimal - 1))}
						{@const totalCost = totalUpgradeCost + rollCost}
						{@const maxBudget = formPrice * 1.5}
						<p class="mt-1 text-xs text-gray-500">
							roll cost: {rollCost} scraps · upgrades to 100%: {Math.round(totalUpgradeCost)} scraps
						</p>
						<p
							class="mt-1 text-xs {totalCost > maxBudget
								? 'font-bold text-red-600'
								: 'text-gray-500'}"
						>
							total: {Math.round(totalCost)} scraps ({upgradesNeeded} upgrades + roll) · budget: {Math.round(
								maxBudget
							)} (1.5×)
							{#if totalCost > maxBudget}· over budget!{/if}
						</p>
					{/if}
				</div>

				<div class="grid grid-cols-2 gap-4">
					<div>
						<label for="count" class="mb-1 block text-sm font-bold">stock count</label>
						<input
							id="count"
							type="number"
							value={formCount}
							oninput={(e) => updateFromStock(parseInt(e.currentTarget.value) || 0)}
							min="0"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
						<p class="mt-1 text-xs text-gray-500">affects rarity calculation</p>
					</div>
					<div>
						<label for="category" class="mb-1 block text-sm font-bold">categories</label>
						<input
							id="category"
							type="text"
							bind:value={formCategory}
							placeholder="stickers, hardware"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
					</div>
				</div>

				<div class="grid grid-cols-2 gap-4">
					<div>
						<label for="baseProbability" class="mb-1 block text-sm font-bold"
							>base probability (%)</label
						>
						<input
							id="baseProbability"
							type="number"
							bind:value={formBaseProbability}
							min="0.1"
							max="100"
							step="0.1"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
					</div>
					<div>
						<label for="boostAmount" class="mb-1 block text-sm font-bold"
							>boost per upgrade (%)</label
						>
						<input
							id="boostAmount"
							type="number"
							bind:value={formBoostAmount}
							min="1"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
					</div>
				</div>

				<div class="grid grid-cols-2 gap-4">
					<div>
						<label for="baseUpgradeCost" class="mb-1 block text-sm font-bold"
							>base upgrade cost</label
						>
						<input
							id="baseUpgradeCost"
							type="number"
							bind:value={formBaseUpgradeCost}
							min="0"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
						<p class="mt-1 text-xs text-gray-500">auto-set to 10% of price</p>
					</div>
					<div>
						<label for="costMultiplier" class="mb-1 block text-sm font-bold"
							>cost multiplier (%)</label
						>
						<input
							id="costMultiplier"
							type="number"
							bind:value={formCostMultiplier}
							min="100"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
						<p class="mt-1 text-xs text-gray-500">115 = 1.15x per upgrade</p>
					</div>
				</div>
			</div>

			<div class="mt-6 flex gap-3">
				<button
					onclick={closeModal}
					disabled={saving}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={handleSubmit}
					disabled={saving}
					class="flex-1 cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
				>
					{saving ? $t.common.saving : editingItem ? $t.common.save : $t.common.create}
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Lootbox Create/Edit Modal -->
{#if showLootboxModal}
	<div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
		<div
			class="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-2xl border-4 border-black bg-white p-6"
		>
			<div class="mb-6 flex items-center justify-between">
				<h2 class="text-2xl font-bold">
					{editingLootbox ? $t.lootbox.editLootbox : $t.lootbox.createLootbox}
				</h2>
				<button
					onclick={closeLootboxModal}
					class="cursor-pointer rounded-lg p-2 transition-colors hover:bg-gray-100"
				>
					<X size={20} />
				</button>
			</div>

			{#if lbError}
				<div class="mb-4 rounded-lg border-2 border-red-600 bg-red-50 p-3 text-sm text-red-600">
					{lbError}
				</div>
			{/if}

			<div class="space-y-4">
				<div>
					<label for="lb-name" class="mb-1 block text-sm font-bold">name</label>
					<input
						id="lb-name"
						type="text"
						bind:value={lbName}
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
				</div>

				<div>
					<label for="lb-image" class="mb-1 block text-sm font-bold">image URL</label>
					<input
						id="lb-image"
						type="text"
						bind:value={lbImage}
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
				</div>

				<div>
					<label for="lb-description" class="mb-1 block text-sm font-bold">description</label>
					<textarea
						id="lb-description"
						bind:value={lbDescription}
						rows="2"
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
				</div>

				<div class="grid grid-cols-2 gap-4">
					<div>
						<label for="lb-price" class="mb-1 block text-sm font-bold">{$t.lootbox.price} (scraps)</label>
						<input
							id="lb-price"
							type="number"
							bind:value={lbPrice}
							min="1"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
					</div>
					<div>
						<label for="lb-category" class="mb-1 block text-sm font-bold">categories</label>
						<input
							id="lb-category"
							type="text"
							bind:value={lbCategory}
							placeholder="lootbox, stickers"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
					</div>
				</div>

				<!-- Item Selection -->
				<div>
					<div class="mb-2 flex items-center justify-between">
						<label class="block text-sm font-bold">{$t.lootbox.selectItems}</label>
						<button
							onclick={autoFillPercentages}
							disabled={lbSelectedItems.length < 2}
							class="cursor-pointer rounded-full border-4 border-black px-3 py-1 text-xs font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
						>
							{$t.lootbox.autoFill}
						</button>
					</div>

					<div class="max-h-60 overflow-y-auto rounded-lg border-2 border-black p-2">
						{#if items.length === 0}
							<p class="py-4 text-center text-sm text-gray-500">{$t.refinery.noItemsAvailable}</p>
						{:else}
							{#each items as item}
								{@const isSelected = lbSelectedItems.some((i) => i.shopItemId === item.id)}
								{@const selectedItem = lbSelectedItems.find((i) => i.shopItemId === item.id)}
								<div
									class="flex items-center gap-3 rounded-lg p-2 {isSelected
										? 'bg-purple-50'
										: 'hover:bg-gray-50'}"
								>
									<input
										type="checkbox"
										checked={isSelected}
										onchange={() => toggleLootboxItem(item.id)}
										class="h-4 w-4 cursor-pointer"
									/>
									<img
										src={item.image}
										alt={item.name}
										class="h-8 w-8 shrink-0 rounded object-cover"
									/>
									<span class="flex-1 text-sm font-medium">{item.name}</span>
									<span class="flex items-center gap-1 text-xs text-gray-500"
										><Spool size={12} />{item.price}</span
									>
									{#if isSelected && selectedItem}
										<div class="flex items-center gap-1">
											<input
												type="number"
												value={selectedItem.percentage}
												oninput={(e) =>
													updateLbItemPercentage(
														item.id,
														parseInt(e.currentTarget.value) || 0
													)}
												min="1"
												max="99"
												class="w-16 rounded border-2 border-black px-2 py-1 text-center text-sm focus:border-dashed focus:outline-none"
											/>
											<span class="text-sm font-bold">%</span>
										</div>
									{/if}
								</div>
							{/each}
						{/if}
					</div>

					<!-- Percentage total -->
					{#if lbSelectedItems.length > 0}
						<div class="mt-2 flex items-center justify-between text-sm">
							<span class="text-gray-500"
								>{lbSelectedItems.length} {$t.lootbox.items} selected</span
							>
							<span
								class="font-bold {lbPercentageSum === 100
									? 'text-green-600'
									: 'text-red-600'}"
							>
								{$t.lootbox.totalPercentage}: {lbPercentageSum}%
								{#if lbPercentageSum !== 100}
									({$t.lootbox.mustSumTo100})
								{/if}
							</span>
						</div>
					{/if}
				</div>
			</div>

			<div class="mt-6 flex gap-3">
				<button
					onclick={closeLootboxModal}
					disabled={lbSaving}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={handleLootboxSubmit}
					disabled={lbSaving}
					class="flex-1 cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
				>
					{lbSaving
						? $t.common.saving
						: editingLootbox
							? $t.common.save
							: $t.common.create}
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Delete Item Confirm -->
{#if deleteConfirmId}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (deleteConfirmId = null)}
		onkeydown={(e) => e.key === 'Escape' && (deleteConfirmId = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">{$t.admin.confirmDelete}</h2>
			<p class="mb-6 text-gray-600">
				are you sure you want to delete this item? <span class="mt-2 block text-red-600"
					>this action cannot be undone.</span
				>
			</p>
			<div class="flex gap-3">
				<button
					onclick={() => (deleteConfirmId = null)}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={confirmDelete}
					class="flex-1 cursor-pointer rounded-full border-4 border-black bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed"
				>
					{$t.common.delete}
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Delete Lootbox Confirm -->
{#if deleteLootboxConfirmId}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (deleteLootboxConfirmId = null)}
		onkeydown={(e) => e.key === 'Escape' && (deleteLootboxConfirmId = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">{$t.admin.confirmDelete}</h2>
			<p class="mb-6 text-gray-600">
				are you sure you want to delete this lootbox? <span class="mt-2 block text-red-600"
					>this action cannot be undone.</span
				>
			</p>
			<div class="flex gap-3">
				<button
					onclick={() => (deleteLootboxConfirmId = null)}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={confirmDeleteLootbox}
					class="flex-1 cursor-pointer rounded-full border-4 border-black bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed"
				>
					{$t.common.delete}
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Error Modal -->
{#if errorModal}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (errorModal = null)}
		onkeydown={(e) => e.key === 'Escape' && (errorModal = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">{$t.common.error}</h2>
			<p class="mb-6 text-gray-600">{errorModal}</p>
			<button
				onclick={() => (errorModal = null)}
				class="w-full cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed"
			>
				{$t.common.ok}
			</button>
		</div>
	</div>
{/if}
