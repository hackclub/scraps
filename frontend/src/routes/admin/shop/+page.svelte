<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		Plus,
		Pencil,
		Trash2,
		X,
		Spool,
		TrendingUp,
		AlertTriangle,
		ShieldCheck,
		RotateCcw,
		Upload,
		Dices,
		PackageOpen
	} from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';
	import { isInfiniteStock, stockLabel } from '$lib/utils';

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
		boostAmount: number;
		rollCostOverride: number | null;
		perRollMultiplier?: number | null;
		fulfillmentCost?: number | null;
		sizeVariants?: { name: string; count: number }[];
		createdAt: string;
		updatedAt: string;
	}

	interface User {
		id: number;
		role: string;
	}

	interface Gachapon {
		id: number;
		name: string;
		description: string | null;
		image: string | null;
		price: number;
		itemIds: number[];
	}

	interface EVResult {
		upgradeLevel: number;
		boostPercent: number;
		effectiveProbability: number;
		actualWinChance: number;
		rollCost: number;
		upgradeCostCumulative: number;
		expectedRolls: number;
		expectedRollCost: number;
		expectedTotalCost: number;
		evRatio: number;
	}

	interface EVSummary {
		results: EVResult[];
		bestPlayerLevel: number;
		bestPlayerCost: number;
		bestPlayerRatio: number;
		isUnderpriced: boolean;
		marginPercent: number;
	}

	let user = $state<User | null>(null);
	let items = $state<ShopItem[]>([]);
	let loading = $state(true);
	let saving = $state(false);

	let existingCategories = $derived.by(() => {
		const set = new Set<string>();
		items.forEach((i) =>
			i.category
				.split(',')
				.map((c) => c.trim())
				.filter(Boolean)
				.forEach((c) => set.add(c))
		);
		return Array.from(set).sort();
	});

	let showModal = $state(false);
	let editingItem = $state<ShopItem | null>(null);

	let formName = $state('');
	let formImage = $state('');
	let uploadingImage = $state(false);

	async function handleImageUpload(event: Event) {
		const file = (event.target as HTMLInputElement).files?.[0];
		if (!file) return;
		if (file.size > 5 * 1024 * 1024) {
			formError = 'Image must be under 5MB';
			return;
		}
		uploadingImage = true;
		formError = null;
		try {
			const fd = new FormData();
			fd.append('file', file);
			const res = await fetch(`${API_URL}/upload/image`, {
				method: 'POST',
				credentials: 'include',
				body: fd
			});
			const data = await res.json();
			if (data.error) throw new Error(data.error);
			formImage = data.url;
		} catch (e) {
			formError = e instanceof Error ? e.message : 'Upload failed';
		} finally {
			uploadingImage = false;
		}
	}
	let formDescription = $state('');
	let formPrice = $state(0);
	let formPriceOverride = $state(false);
	let formCategory = $state('');
	let formCount = $state(0);
	let formInfiniteStock = $derived(formCount < 0);
	let formSizeVariants = $state<{ name: string; count: number }[]>([]);
	let formIsShirt = $derived(
		formCategory
			.toLowerCase()
			.split(',')
			.map((c) => c.trim())
			.includes('shirt')
	);

	function toggleInfiniteStock(infinite: boolean) {
		updateFromStock(infinite ? -1 : 0);
	}

	function addSizeVariant() {
		formSizeVariants = [...formSizeVariants, { name: '', count: 0 }];
	}

	function removeSizeVariant(index: number) {
		formSizeVariants = formSizeVariants.filter((_, i) => i !== index);
	}

	function randomInt(min: number, max: number) {
		return Math.round(min + Math.random() * (max - min));
	}

	async function randomizeOdds() {
		formBaseProbability = randomInt(5, 80);
		formRollCostOverride = null;
		await recalculatePricing();
	}

	function addCategoryTag(cat: string) {
		const current = formCategory
			.split(',')
			.map((c) => c.trim())
			.filter(Boolean);
		if (!current.includes(cat)) {
			formCategory = [...current, cat].join(', ');
		}
	}
	let formBaseProbability = $state(50);
	let formBaseUpgradeCost = $state(10);
	let formBoostAmount = $state(1);
	let formRollCostOverride = $state<number | null>(null);
	let formFulfillmentCost = $state<number | null>(null);
	let formMonetaryValue = $state(0);
	let formError = $state<string | null>(null);
	// eslint-disable-next-line @typescript-eslint/no-unused-vars -- used in template
	let errorModal = $state<string | null>(null);

	const SCRAPS_PER_HOUR = 64;
	const DOLLARS_PER_HOUR = 4;
	const SCRAPS_PER_DOLLAR = SCRAPS_PER_HOUR / DOLLARS_PER_HOUR;

	function calculateRollCost(
		basePrice: number,
		effectiveProbability: number,
		rollCostOverride?: number | null,
		baseProbability?: number
	): number {
		if (rollCostOverride != null && rollCostOverride > 0) {
			return rollCostOverride;
		}
		const baseProb = baseProbability ?? effectiveProbability;
		return Math.max(1, Math.round(basePrice * (baseProb / 100)));
	}

	// Must match backend computeRollThreshold exactly
	function computeRollThreshold(probability: number): number {
		return Math.max(1, Math.floor((probability * 17) / 20));
	}

	// Must match backend calculateShopItemPricing exactly
	function calculatePricing(monetaryValue: number, stockCount: number, priceOverride?: number) {
		const price = priceOverride ?? Math.round(monetaryValue * SCRAPS_PER_DOLLAR);

		const priceRarityFactor = Math.max(0, 1 - monetaryValue / 100);
		const stockRarityFactor = stockCount < 0 ? 1 : Math.min(1, stockCount / 20);
		const baseProbability = Math.max(
			1,
			Math.min(80, Math.round((priceRarityFactor * 0.4 + stockRarityFactor * 0.6) * 80))
		);

		// eslint-disable-next-line @typescript-eslint/no-unused-vars
		const rollCost = Math.max(1, Math.round(price * (baseProbability / 100)));

		const probabilityGap = 100 - baseProbability;
		const targetUpgrades = Math.max(5, Math.min(20, Math.ceil(monetaryValue / 5)));
		const boostAmount = Math.max(1, Math.round(probabilityGap / targetUpgrades));

		// Upgrades start at 25% of item price and decay by 1.05x per level
		const baseUpgradeCost = Math.max(1, Math.floor(price * 0.25));

		return { price, baseProbability, baseUpgradeCost, boostAmount };
	}

	function simulateEV(
		price: number,
		baseProbability: number,
		baseUpgradeCost: number,
		boostAmount: number,
		rollCostOverride?: number | null
	): EVSummary {
		const results: EVResult[] = [];
		const probabilityGap = 100 - baseProbability;
		const maxUpgrades = boostAmount > 0 ? Math.ceil(probabilityGap / boostAmount) : 0;

		let bestLevel = 0;
		let bestCost = Infinity;

		// backend constants mirrored — no budget cap; upgrades run until 100%.
		const UPGRADE_START_PERCENT = 0.25;
		const UPGRADE_DECAY = 1.05;
		const startCost = baseUpgradeCost || Math.max(1, Math.floor(price * UPGRADE_START_PERCENT));

		for (let k = 0; k <= maxUpgrades; k++) {
			const boostPercent = k * boostAmount;
			const effectiveProbability = Math.min(baseProbability + boostPercent, 100);

			// Cumulative upgrade cost: startCost / 1.05^i per level, decaying.
			let upgradeCostCumulative = 0;
			for (let i = 0; i < k; i++) {
				upgradeCostCumulative += Math.max(1, Math.floor(startCost / Math.pow(UPGRADE_DECAY, i)));
			}

			const rollCost = calculateRollCost(
				price,
				effectiveProbability,
				rollCostOverride,
				baseProbability
			);

			const actualThreshold = computeRollThreshold(effectiveProbability);
			const actualWinChance = actualThreshold / 100;
			const expectedRolls = actualWinChance > 0 ? 1 / actualWinChance : Infinity;
			const expectedRollCost = rollCost * expectedRolls;
			const expectedTotalCost = upgradeCostCumulative + expectedRollCost;
			const evRatio = price > 0 ? expectedTotalCost / price : Infinity;

			const result: EVResult = {
				upgradeLevel: k,
				boostPercent,
				effectiveProbability,
				actualWinChance: Math.round(actualWinChance * 10000) / 100,
				rollCost,
				upgradeCostCumulative,
				expectedRolls: Math.round(expectedRolls * 100) / 100,
				expectedRollCost: Math.round(expectedRollCost),
				expectedTotalCost: Math.round(expectedTotalCost),
				evRatio: Math.round(evRatio * 1000) / 1000
			};

			results.push(result);

			if (expectedTotalCost < bestCost) {
				bestCost = expectedTotalCost;
				bestLevel = k;
			}
		}

		const bestResult = results[bestLevel];
		const isUnderpriced = bestCost < price;

		const marginPercent =
			bestResult && price > 0
				? Math.round(((bestResult.expectedTotalCost - price) / price) * 1000) / 10
				: 0;

		return {
			results,
			bestPlayerLevel: bestLevel,
			bestPlayerCost: Math.round(bestCost),
			bestPlayerRatio: bestResult?.evRatio ?? 0,
			isUnderpriced,
			marginPercent
		};
	}

	function getItemEVSummary(item: ShopItem): EVSummary {
		return simulateEV(
			item.price,
			item.baseProbability,
			item.baseUpgradeCost,
			item.boostAmount,
			item.rollCostOverride
		);
	}

	let formEV = $derived(
		formPrice > 0
			? simulateEV(
					formPrice,
					formBaseProbability,
					formBaseUpgradeCost,
					formBoostAmount,
					formRollCostOverride
				)
			: null
	);

	let showDetailedEV = $state(false);

	// Optimal pricing is fetched from the server so the UI always matches backend logic.
	// When price is overridden, request EV-safe upgrade costs computed on the server.
	let optimalPricing = $state<{
		price: number;
		baseProbability: number;
		baseUpgradeCost: number;
		boostAmount: number;
		rollCost?: number;
		expectedRollsAtBase?: number;
		expectedSpendAtBase?: number;
		dollarCost?: number;
		scrapsPerDollar?: number;
	} | null>(null);

	let hasCustomPricing = $derived(
		formPrice > 0 &&
			(formPrice !== optimalPricing?.price ||
				formBaseProbability !== optimalPricing?.baseProbability ||
				formBaseUpgradeCost !== optimalPricing?.baseUpgradeCost ||
				formBoostAmount !== optimalPricing?.boostAmount)
	);

	async function recalculatePricing(applyToForm = true) {
		// Nothing to price until a dollar value is entered — skip the call (and the
		// 400 it would return) rather than spam the console.
		if (!(formMonetaryValue > 0)) {
			optimalPricing = null;
			return;
		}
		// Call server-side compute endpoint so admin previews exactly match backend
		try {
			const body = {
				dollarCost: formMonetaryValue,
				baseProbability: formBaseProbability,
				stockCount: formCount
			};
			const res = await fetch(`${API_URL}/admin/shop/compute-pricing`, {
				method: 'POST',
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(body)
			});
			if (!res.ok) {
				// Fall back gracefully to client-side calculation if server call fails
				console.error('[ADMIN] compute-pricing failed', res.status);
				const pricing = calculatePricing(
					formMonetaryValue,
					formCount,
					formPriceOverride ? formPrice : undefined
				);
				optimalPricing = pricing;
				if (applyToForm) {
					if (!formPriceOverride) {
						formPrice = pricing.price;
					}
					formBaseProbability = pricing.baseProbability;
					formBaseUpgradeCost = pricing.baseUpgradeCost;
					formBoostAmount = pricing.boostAmount;
				}
				return;
			}
			const raw = await res.json();
			// Server sends scrapsPrice / rollCostEstimate; normalise to the shape
			// the form uses so `formPrice` doesn't come back undefined (→ NaN).
			const pricing = {
				...raw,
				price: raw.scrapsPrice ?? raw.price,
				rollCost: raw.rollCostEstimate ?? raw.rollCost
			};
			optimalPricing = pricing;
			if (applyToForm) {
				if (!formPriceOverride) {
					formPrice = pricing.price;
				}
				formBaseProbability = pricing.baseProbability;
				formBaseUpgradeCost = pricing.baseUpgradeCost;
				formBoostAmount = pricing.boostAmount;
			}
		} catch (err) {
			console.error('[ADMIN] recalculatePricing error', err);
			// Fallback to local computation on network/other errors
			const pricing = calculatePricing(
				formMonetaryValue,
				formCount,
				formPriceOverride ? formPrice : undefined
			);
			optimalPricing = pricing;
			if (applyToForm) {
				if (!formPriceOverride) {
					formPrice = pricing.price;
				}
				formBaseProbability = pricing.baseProbability;
				formBaseUpgradeCost = pricing.baseUpgradeCost;
				formBoostAmount = pricing.boostAmount;
			}
		}
	}

	async function updateFromMonetary(value: number) {
		formMonetaryValue = value;
		if (!formPriceOverride) {
			formPrice = Math.round(value * SCRAPS_PER_DOLLAR);
		}
		await recalculatePricing(!editingItem);
	}

	async function updateFromStock(value: number) {
		formCount = value;
		await recalculatePricing(!editingItem);
	}

	async function updatePriceOverride(value: number) {
		formPrice = value;
		formPriceOverride = true;
		await recalculatePricing(!editingItem);
	}

	async function clearPriceOverride() {
		formPriceOverride = false;
		formPrice = Math.round(formMonetaryValue * SCRAPS_PER_DOLLAR);
		await recalculatePricing(!editingItem);
	}

	let deleteConfirmId = $state<number | null>(null);

	onMount(async () => {
		user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}

		await fetchItems();
		await fetchGachapons();
	});

	let gachapons = $state<Gachapon[]>([]);
	let gachaponsLoading = $state(true);
	let showGachaponModal = $state(false);
	let editingGachapon = $state<Gachapon | null>(null);
	let gachaName = $state('');
	let gachaDescription = $state('');
	let gachaImage = $state('');
	let gachaUploadingImage = $state(false);
	let gachaPrice = $state(0);
	let gachaSelectedItemIds = $state<Set<number>>(new Set());
	let gachaSaving = $state(false);
	let gachaError = $state<string | null>(null);
	let gachaDeleteConfirmId = $state<number | null>(null);

	async function fetchGachapons() {
		gachaponsLoading = true;
		try {
			const res = await fetch(`${API_URL}/admin/shop/gachapons`, { credentials: 'include' });
			if (res.ok) gachapons = await res.json();
		} catch (e) {
			console.error('Failed to load gachapons:', e);
		} finally {
			gachaponsLoading = false;
		}
	}

	function openCreateGachapon() {
		editingGachapon = null;
		gachaName = '';
		gachaDescription = '';
		gachaImage = '';
		gachaPrice = 0;
		gachaSelectedItemIds = new Set();
		gachaError = null;
		showGachaponModal = true;
	}

	function openEditGachapon(g: Gachapon) {
		editingGachapon = g;
		gachaName = g.name;
		gachaDescription = g.description ?? '';
		gachaImage = g.image ?? '';
		gachaPrice = g.price;
		gachaSelectedItemIds = new Set(g.itemIds);
		gachaError = null;
		showGachaponModal = true;
	}

	function closeGachaponModal() {
		showGachaponModal = false;
		editingGachapon = null;
	}

	function toggleGachaItem(id: number) {
		const next = new Set(gachaSelectedItemIds);
		if (next.has(id)) next.delete(id);
		else next.add(id);
		gachaSelectedItemIds = next;
	}

	async function handleGachaImageUpload(event: Event) {
		const file = (event.target as HTMLInputElement).files?.[0];
		if (!file) return;
		if (file.size > 5 * 1024 * 1024) {
			gachaError = 'Image must be under 5MB';
			return;
		}
		gachaUploadingImage = true;
		gachaError = null;
		try {
			const fd = new FormData();
			fd.append('file', file);
			const res = await fetch(`${API_URL}/upload/image`, {
				method: 'POST',
				credentials: 'include',
				body: fd
			});
			const data = await res.json();
			if (data.error) throw new Error(data.error);
			gachaImage = data.url;
		} catch (e) {
			gachaError = e instanceof Error ? e.message : 'Upload failed';
		} finally {
			gachaUploadingImage = false;
		}
	}

	async function handleGachaponSubmit() {
		if (!gachaName.trim()) {
			gachaError = 'Name is required';
			return;
		}
		if (gachaPrice <= 0) {
			gachaError = 'Price must be positive';
			return;
		}
		if (gachaSelectedItemIds.size === 0) {
			gachaError = 'Select at least one item';
			return;
		}

		gachaSaving = true;
		gachaError = null;

		try {
			const url = editingGachapon
				? `${API_URL}/admin/shop/gachapons/${editingGachapon.id}`
				: `${API_URL}/admin/shop/gachapons`;

			const response = await fetch(url, {
				method: editingGachapon ? 'PUT' : 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({
					name: gachaName,
					description: gachaDescription,
					image: gachaImage,
					price: gachaPrice,
					itemIds: Array.from(gachaSelectedItemIds)
				})
			});

			if (response.ok) {
				closeGachaponModal();
				await fetchGachapons();
			} else {
				const data = await response.json();
				gachaError = data.error || 'Failed to save';
			}
		} catch (_e) {
			gachaError = 'Failed to save gachapon';
		} finally {
			gachaSaving = false;
		}
	}

	function requestDeleteGachapon(id: number) {
		gachaDeleteConfirmId = id;
	}

	async function confirmDeleteGachapon() {
		if (!gachaDeleteConfirmId) return;
		try {
			const response = await fetch(`${API_URL}/admin/shop/gachapons/${gachaDeleteConfirmId}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			if (response.ok) {
				await fetchGachapons();
			} else {
				const data = await response.json();
				errorModal = data.error || 'Failed to delete gachapon';
			}
		} catch (e) {
			console.error('Failed to delete gachapon:', e);
			errorModal = 'Failed to delete gachapon';
		} finally {
			gachaDeleteConfirmId = null;
		}
	}

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

	async function openCreateModal() {
		editingItem = null;
		formName = '';
		formImage = '';
		formDescription = '';
		formPrice = 0;
		formPriceOverride = false;
		formMonetaryValue = 0;
		formCategory = '';
		formCount = 0;
		formBaseProbability = 50;
		formBaseUpgradeCost = 10;
		formBoostAmount = 1;
		formRollCostOverride = null;
		formFulfillmentCost = null;
		formSizeVariants = [];
		formError = null;
		showDetailedEV = false;
		showModal = true;
		// Prefetch canonical pricing so modal EV/optimal UI matches backend — never
		// let a pricing hiccup keep the modal from opening.
		recalculatePricing().catch((e) => console.error('[ADMIN] pricing prefetch failed', e));
	}

	async function openEditModal(item: ShopItem) {
		editingItem = item;
		formName = item.name;
		formImage = item.image;
		formDescription = item.description;
		formMonetaryValue = Math.round((item.price / SCRAPS_PER_DOLLAR) * 100) / 100;
		const autoPrice = Math.round(formMonetaryValue * SCRAPS_PER_DOLLAR);
		formPrice = item.price;
		formPriceOverride = item.price !== autoPrice;
		formCategory = item.category;
		formCount = item.count;
		formBaseProbability = item.baseProbability;
		formBaseUpgradeCost = item.baseUpgradeCost;
		formBoostAmount = item.boostAmount ?? 1;
		formRollCostOverride = item.rollCostOverride ?? null;
		formFulfillmentCost = item.fulfillmentCost ?? null;
		formSizeVariants = item.sizeVariants ? item.sizeVariants.map((v) => ({ ...v })) : [];
		formError = null;
		showDetailedEV = false;
		showModal = true;
		// Comparison pricing only — must not block the modal from opening.
		recalculatePricing(false).catch((e) => console.error('[ADMIN] pricing prefetch failed', e));
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
					boostAmount: formBoostAmount,
					rollCostOverride: formRollCostOverride,
					fulfillmentCost: formFulfillmentCost,
					sizeVariants: formIsShirt
						? formSizeVariants.filter((v) => v.name.trim())
						: []
				})
			});

			if (response.ok) {
				closeModal();
				await fetchItems();
			} else {
				const data = await response.json();
				formError = data.error || 'Failed to save';
			}
		} catch (_e) {
			formError = 'Failed to save item';
		} finally {
			saving = false;
		}
	}

	function requestDelete(id: number) {
		deleteConfirmId = id;
	}

	// eslint-disable-next-line @typescript-eslint/no-unused-vars -- called from template
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
		<div class="flex gap-3">
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
		<div class="flex items-center gap-2 text-sm">
			<Spool size={16} />
			<span class="font-bold">{Math.round(SCRAPS_PER_HOUR)} scraps</span>
			<span class="text-gray-500">≈ 1 hour of tracked work ≈ ${DOLLARS_PER_HOUR.toFixed(2)}</span>
		</div>
	</div>

	<div class="mb-8 rounded-2xl border-4 border-black p-4">
		<h3 class="mb-3 flex items-center gap-2 font-bold">
			<TrendingUp size={18} />
			pricing model reference
		</h3>
		<div class="grid grid-cols-1 gap-4 text-sm md:grid-cols-3">
			<div class="rounded-lg bg-gray-100 p-3">
				<div class="mb-1 text-xs text-gray-500">roll cost</div>
				<div class="font-bold">price × effective% / 100</div>
			</div>
			<div class="rounded-lg bg-gray-100 p-3">
				<div class="mb-1 text-xs text-gray-500">upgrades</div>
				<div class="font-bold">continue until effective% = 100</div>
			</div>
			<div class="rounded-lg bg-gray-100 p-3">
				<div class="mb-1 text-xs text-gray-500">upgrade cost</div>
				<div class="font-bold">base ÷ 1.05^level, decaying</div>
			</div>
		</div>
		<p class="mt-2 text-xs text-gray-500">
			roll cost scales with effective probability (including upgrades). upgrades raise the win chance
			and the roll cost together, with no scraps cap — a user can keep upgrading until they reach 100%
			effective probability.
		</p>
	</div>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if items.length === 0}
		<div class="py-12 text-center text-gray-500">{$t.refinery.noItemsAvailable}</div>
	{:else}
		<div class="grid gap-4">
			{#each items as item}
				{@const ev = getItemEVSummary(item)}
				<div
					class="rounded-2xl border-4 p-4 transition-all {ev.isUnderpriced
						? 'border-red-600 bg-red-50'
						: 'border-black'}"
				>
					<div class="flex items-center gap-4">
						<img
							src={item.image}
							alt={item.name}
							class="h-20 w-20 shrink-0 rounded-lg border-2 border-black object-cover"
						/>
						<div class="min-w-0 flex-1">
							<h3 class="text-xl font-bold">{item.name}</h3>
							<p class="text-sm wrap-break-word text-gray-600">{item.description}</p>
							<div class="mt-1 flex flex-wrap items-center gap-2 text-sm">
								<span class="font-bold">${(item.price / SCRAPS_PER_DOLLAR).toFixed(2)}</span>
								<span class="text-gray-500">·</span>
								<span class="flex items-center gap-1 font-bold"
									><Spool size={16} />{item.price}</span
								>
								{#each item.category
									.split(',')
									.map((c) => c.trim())
									.filter(Boolean) as cat}
									<span class="rounded-full bg-gray-100 px-2 py-0.5">{cat}</span>
								{/each}
								<span class="text-gray-500"
									>{isInfiniteStock(item.count) ? '∞' : stockLabel(item.count)} in stock</span
								>
								<span class="text-gray-500">·</span>
								<span class="text-gray-500">{item.baseProbability}% base</span>
								<span class="text-gray-500">·</span>
								<span class="text-gray-500">+{item.boostAmount ?? 1}%/upgrade</span>
								<span class="text-gray-500">·</span>
								<span class="text-gray-500"
									>~{(item.price / SCRAPS_PER_HOUR).toFixed(1)} hrs to earn</span
								>
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

					<!-- EV Summary Bar -->
					<div
						class="mt-3 flex flex-wrap items-center gap-3 rounded-lg px-3 py-2 text-xs {ev.isUnderpriced
							? 'bg-red-100'
							: 'bg-gray-100'}"
					>
						<div class="flex-1">
							<div class="mb-1 text-xs text-gray-500">best player strategy</div>
							<div class="flex items-center gap-3">
								<div class="font-bold">level {ev.bestPlayerLevel}</div>
								<div class="text-gray-600">cost {ev.bestPlayerCost} scraps</div>
								{#if ev.isUnderpriced}
									<div class="font-bold text-red-600">underpriced</div>
								{/if}
								<div class="text-gray-500">margin {ev.marginPercent}%</div>
							</div>
						</div>
						<div class="flex gap-2">
							<button
								onclick={() => (showDetailedEV = !showDetailedEV)}
								class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
							>
								{showDetailedEV ? 'hide details' : 'show details'}
							</button>
						</div>
					</div>

					{#if showDetailedEV}
						<div class="mt-3">
							<table class="w-full text-sm">
								<thead>
									<tr class="text-left text-xs text-gray-600">
										<th class="py-2">level</th>
										<th>eff%</th>
										<th>roll cost</th>
										<th>upgrade cost</th>
										<th>expected rolls</th>
										<th>expected total</th>
									</tr>
								</thead>
								<tbody>
									{#each ev.results as r}
										<tr class="border-t">
											<td class="py-2">{r.upgradeLevel}</td>
											<td>{r.effectiveProbability}%</td>
											<td>{r.rollCost}</td>
											<td>{r.upgradeCostCumulative}</td>
											<td>{r.expectedRolls}</td>
											<td>{r.expectedTotalCost}</td>
										</tr>
									{/each}
								</tbody>
							</table>
						</div>
					{/if}
				</div>
			{/each}
		</div>
	{/if}

	<div class="mt-12 mb-8 flex items-center justify-between">
		<div>
			<h2 class="mb-1 flex items-center gap-2 text-2xl font-bold"><PackageOpen size={22} /> gachapons</h2>
			<p class="text-gray-600">
				guaranteed-win bundles — pay a premium, get one random item from the pool
			</p>
		</div>
		<button
			onclick={openCreateGachapon}
			class="flex cursor-pointer items-center gap-2 rounded-full bg-black px-6 py-3 font-bold text-white transition-all duration-200 hover:bg-gray-800"
		>
			<Plus size={20} />
			new gachapon
		</button>
	</div>

	{#if gachaponsLoading}
		<div class="py-8 text-center text-gray-500">loading…</div>
	{:else if gachapons.length === 0}
		<p class="rounded-2xl border-4 border-dashed border-gray-300 p-8 text-center text-gray-400">
			no gachapons yet
		</p>
	{:else}
		<div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
			{#each gachapons as g (g.id)}
				<div class="overflow-hidden rounded-2xl border-4 border-black">
					{#if g.image}
						<img src={g.image} alt={g.name} class="h-32 w-full object-cover" />
					{:else}
						<div class="flex h-32 w-full items-center justify-center bg-gray-100">
							<PackageOpen size={32} class="text-gray-300" />
						</div>
					{/if}
					<div class="p-4">
						<h3 class="mb-1 text-lg font-bold">{g.name}</h3>
						{#if g.description}
							<p class="mb-2 line-clamp-2 text-sm text-gray-600">{g.description}</p>
						{/if}
						<div class="mb-3 flex items-center gap-2 text-sm">
							<Spool size={16} />
							<span class="font-bold">{g.price}</span>
							<span class="text-gray-500"
								>· {g.itemIds.length} item{g.itemIds.length === 1 ? '' : 's'} in pool</span
							>
						</div>
						<div class="flex gap-2">
							<button
								onclick={() => openEditGachapon(g)}
								class="flex flex-1 cursor-pointer items-center justify-center gap-1 rounded-full border-2 border-black px-3 py-1.5 text-sm font-bold hover:bg-gray-100"
							>
								<Pencil size={14} /> edit
							</button>
							<button
								onclick={() => requestDeleteGachapon(g.id)}
								class="flex cursor-pointer items-center justify-center gap-1 rounded-full border-2 border-red-600 px-3 py-1.5 text-sm font-bold text-red-600 hover:bg-red-50"
							>
								<Trash2 size={14} />
							</button>
						</div>
					</div>
				</div>
			{/each}
		</div>
	{/if}
</div>

{#if showModal}
					<div
						class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
						onclick={(e) => e.target === e.currentTarget && closeModal()}
						onkeydown={(e) => e.key === 'Escape' && closeModal()}
						role="dialog"
						tabindex="-1"
					>
						<div
							class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border-4 border-black bg-white p-6"
						>
							<div class="mb-6 flex items-center justify-between">
								<h2 class="text-2xl font-bold">
									{editingItem ? $t.admin.editItem : $t.admin.addItem}
								</h2>
								<button
									onclick={closeModal}
									class="cursor-pointer rounded-lg p-2 transition-colors hover:bg-gray-100"
								>
									<X size={20} />
								</button>
							</div>

							{#if formError}
								<div
									class="mb-4 rounded-lg border-2 border-red-600 bg-red-50 p-3 text-sm text-red-600"
								>
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
									<span class="mb-1 block text-sm font-bold">image</span>
									<div class="flex items-center gap-3">
										{#if formImage}
											<img
												src={formImage}
												alt=""
												class="h-16 w-16 shrink-0 rounded-lg border-2 border-black object-cover"
											/>
										{/if}
										<label
											class="flex cursor-pointer items-center gap-2 rounded-lg border-2 border-black px-4 py-2 font-bold transition-all hover:border-dashed {uploadingImage
												? 'opacity-50'
												: ''}"
										>
											<Upload size={16} />
											{uploadingImage ? 'uploading…' : formImage ? 'replace' : 'upload'}
											<input
												type="file"
												accept="image/*"
												onchange={handleImageUpload}
												disabled={uploadingImage}
												class="hidden"
											/>
										</label>
									</div>
									<input
										type="text"
										bind:value={formImage}
										placeholder="…or paste an image URL"
										class="mt-2 w-full rounded-lg border-2 border-black px-4 py-2 text-sm focus:border-dashed focus:outline-none"
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

								<div class="grid grid-cols-2 gap-4">
									<div>
										<label for="monetaryValue" class="mb-1 block text-sm font-bold">value ($)</label
										>
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
											auto = {Math.round(formMonetaryValue * SCRAPS_PER_DOLLAR)} scraps
										</p>
									</div>

									<div>
										<label for="scrapsPrice" class="mb-1 block text-sm font-bold"
											>price (scraps)
											{#if formPriceOverride}
												<span class="ml-1 text-xs font-normal text-yellow-600">overridden</span>
											{/if}
										</label>
										<input
											id="scrapsPrice"
											type="number"
											value={formPrice}
											oninput={(e) => updatePriceOverride(parseInt(e.currentTarget.value) || 0)}
											min="1"
											class="w-full rounded-lg border-2 px-4 py-2 focus:border-dashed focus:outline-none {formPriceOverride
												? 'border-yellow-500'
												: 'border-black'}"
										/>
										{#if formPriceOverride}
											<button
												onclick={clearPriceOverride}
												class="mt-1 cursor-pointer text-xs font-bold text-yellow-600 underline"
												>reset to auto ({Math.round(formMonetaryValue * SCRAPS_PER_DOLLAR)})</button
											>
										{:else}
											<p class="mt-1 text-xs text-gray-500">
												~{(formPrice / SCRAPS_PER_HOUR).toFixed(1)} hrs to earn
											</p>
										{/if}
									</div>
								</div>

								<div>
									<label for="fulfillmentCost" class="mb-1 block text-sm font-bold"
										>fulfillment cost ($)</label
									>
									<input
										id="fulfillmentCost"
										type="number"
										min="0"
										step="0.01"
										value={formFulfillmentCost ?? ''}
										oninput={(e) => {
											const v = e.currentTarget.value;
											formFulfillmentCost = v === '' ? null : parseFloat(v);
										}}
										placeholder="what it actually costs to ship one"
										class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
									/>
									<p class="mt-1 text-xs text-gray-500">manual — not derived from value</p>
								</div>

								<div class="grid grid-cols-2 gap-4">
									<div>
										<label for="count" class="mb-1 block text-sm font-bold">stock count</label>
										{#if formInfiniteStock}
											<div
												class="flex w-full items-center justify-between rounded-lg border-2 border-black bg-gray-50 px-4 py-2"
											>
												<span class="font-bold text-gray-500">∞ unlimited</span>
											</div>
										{:else}
											<input
												id="count"
												type="number"
												value={formCount}
												oninput={(e) => updateFromStock(parseInt(e.currentTarget.value) || 0)}
												min="0"
												class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
											/>
										{/if}
										<label class="mt-1 flex cursor-pointer items-center gap-2 text-xs text-gray-500">
											<input
												type="checkbox"
												checked={formInfiniteStock}
												onchange={(e) => toggleInfiniteStock(e.currentTarget.checked)}
												class="cursor-pointer"
											/>
											unlimited stock (never sells out)
										</label>
									</div>
									<div>
										<label for="category" class="mb-1 block text-sm font-bold">categories</label>
										<input
											id="category"
											type="text"
											bind:value={formCategory}
											placeholder="e.g. merch, blueprint, hardware"
											class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
										/>
										{#if existingCategories.length > 0}
											<div class="mt-2 flex flex-wrap gap-1">
												{#each existingCategories as cat (cat)}
													<button
														type="button"
														onclick={() => addCategoryTag(cat)}
														class="cursor-pointer rounded-full border-2 border-black px-2 py-0.5 text-xs transition-all hover:bg-gray-100"
													>
														+ {cat}
													</button>
												{/each}
											</div>
										{/if}
										<p class="mt-1 text-xs text-gray-500">
											comma-separate to add more than one — not limited to a fixed list, type
											anything new and it becomes its own category
										</p>
									</div>
								</div>

								{#if formIsShirt}
									<div class="rounded-xl border-2 border-dashed border-black p-3">
										<p class="mb-2 text-sm font-bold">sizes</p>
										<p class="mb-3 text-xs text-gray-500">
											set stock per size — a size with 0 in stock is hidden from users entirely
										</p>
										<div class="flex flex-col gap-2">
											{#each formSizeVariants as variant, i (i)}
												<div class="flex items-center gap-2">
													<input
														type="text"
														bind:value={variant.name}
														placeholder="Small"
														class="flex-1 rounded-lg border-2 border-black px-3 py-1.5 text-sm focus:border-dashed focus:outline-none"
													/>
													<input
														type="number"
														bind:value={variant.count}
														min="0"
														placeholder="0"
														class="w-24 rounded-lg border-2 border-black px-3 py-1.5 text-sm focus:border-dashed focus:outline-none"
													/>
													<button
														type="button"
														onclick={() => removeSizeVariant(i)}
														class="cursor-pointer rounded-lg border-2 border-black p-1.5 hover:bg-gray-100"
														aria-label="remove size"
													>
														<X size={14} />
													</button>
												</div>
											{/each}
										</div>
										<button
											type="button"
											onclick={addSizeVariant}
											class="mt-2 cursor-pointer rounded-full border-2 border-black px-3 py-1 text-xs font-bold hover:bg-gray-100"
										>
											+ add size
										</button>
									</div>
								{/if}

								{#if formMonetaryValue > 0}
									<div
										class="rounded-xl border-2 p-3 {hasCustomPricing
											? 'border-yellow-400 bg-yellow-50'
											: 'border-green-400 bg-green-50'}"
									>
										<div class="flex items-center justify-between">
											<div class="text-xs">
												<span
													class="font-bold {hasCustomPricing
														? 'text-yellow-700'
														: 'text-green-700'}"
												>
													{hasCustomPricing
														? 'custom pricing (differs from optimal)'
														: 'using optimal pricing'}
												</span>
												<span class="ml-2 text-gray-500">
													optimal: {optimalPricing?.baseProbability}% base · +{optimalPricing?.boostAmount}%/upgrade
													· {optimalPricing?.baseUpgradeCost} base upgrade cost
												</span>
											</div>
											{#if hasCustomPricing}
												<button
													onclick={async () => {
														// Apply optimal values into the form
														if (!optimalPricing) return;
														formPrice = optimalPricing.price;
														formBaseProbability = optimalPricing.baseProbability;
														formBaseUpgradeCost = optimalPricing.baseUpgradeCost;
														formBoostAmount = optimalPricing.boostAmount;
														formPriceOverride = false;
														// ensure EV and server parity
														await recalculatePricing();
													}}
													class="flex cursor-pointer items-center gap-1 rounded-full border-2 border-yellow-600 px-3 py-1 text-xs font-bold text-yellow-700 transition-all duration-200 hover:border-dashed"
												>
													<RotateCcw size={12} />
													use optimal
												</button>
											{/if}
										</div>
									</div>
								{/if}

								<button
									type="button"
									onclick={randomizeOdds}
									class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-purple-50 px-4 py-2 text-sm font-bold transition-all hover:border-dashed hover:bg-purple-100"
								>
									<Dices size={16} /> randomize odds (stays within optimal pricing)
								</button>

								<div class="grid grid-cols-2 gap-4">
									<div>
										<label for="baseProbability" class="mb-1 block text-sm font-bold"
											>base probability (%)</label
										>
										<input
											id="baseProbability"
											type="number"
											bind:value={formBaseProbability}
											min="1"
											max="100"
											step="1"
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
											min="0"
											class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
										/>
									</div>
								</div>

								<div>
									<label for="baseUpgradeCost" class="mb-1 block text-sm font-bold"
										>base upgrade cost</label
									>
									<input
										id="baseUpgradeCost"
										type="number"
										bind:value={formBaseUpgradeCost}
										min="1"
										class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
									/>
									<p class="mt-1 text-xs text-gray-500">
										first refinery upgrade; each next one decays ×1.05, no cap until 100%
									</p>
								</div>

								<div>
									<label for="rollCostOverride" class="mb-1 block text-sm font-bold"
										>roll cost override</label
									>
									<div class="flex gap-2">
										<input
											id="rollCostOverride"
											type="number"
											value={formRollCostOverride ?? ''}
											oninput={(e) => {
												const val = e.currentTarget.value;
												formRollCostOverride = val === '' ? null : parseInt(val) || null;
											}}
											min="1"
											placeholder="auto"
											class="w-full rounded-lg border-2 px-4 py-2 focus:border-dashed focus:outline-none"
										/>
										{#if formRollCostOverride != null}
											<button
												onclick={() => (formRollCostOverride = null)}
												class="shrink-0 cursor-pointer rounded-lg border-2 border-yellow-500 px-3 py-2 text-xs font-bold text-yellow-600 transition-all duration-200 hover:border-dashed"
											>
												auto
											</button>
										{/if}
									</div>
								</div>

								{#if formEV}
									<div
										class="mt-4 rounded-xl border-4 p-4 {formEV.isUnderpriced
											? 'border-red-600 bg-red-50'
											: 'border-green-600 bg-green-50'}"
									>
										<div class="mb-3 flex items-center justify-between">
											<h3
												class="flex items-center gap-2 text-sm font-bold {formEV.isUnderpriced
													? 'text-red-700'
													: 'text-green-700'}"
											>
												{#if formEV.isUnderpriced}
													<AlertTriangle size={16} />
													EV ANALYSIS — UNDERPRICED
												{:else}
													<ShieldCheck size={16} />
													EV ANALYSIS — OK
												{/if}
											</h3>
											<button
												onclick={() => (showDetailedEV = !showDetailedEV)}
												class="cursor-pointer text-xs font-bold underline {formEV.isUnderpriced
													? 'text-red-600'
													: 'text-green-700'}"
											>
												{showDetailedEV ? 'hide details' : 'show details'}
											</button>
										</div>

										<div class="grid grid-cols-2 gap-3 text-xs">
											<div>
												<span class="text-gray-500">margin:</span>
												<span class="ml-1 font-bold">+{formEV.marginPercent}%</span>
											</div>
											<div>
												<span class="text-gray-500">base roll cost:</span>
												<span class="ml-1 font-bold"
													>{calculateRollCost(
														formPrice,
														formBaseProbability,
														formRollCostOverride,
														formBaseProbability
													)} scraps</span
												>
												{#if formRollCostOverride != null}
													<span class="ml-1 text-xs text-yellow-600">(overridden)</span>
												{/if}
											</div>
											<div>
												<span class="text-gray-500">player best (lv{formEV.bestPlayerLevel}):</span>
												<span
													class="ml-1 font-bold {formEV.bestPlayerRatio < 1 ? 'text-red-600' : ''}"
													>{formEV.bestPlayerCost} scraps ({formEV.bestPlayerRatio}× price)</span
												>
											</div>
											<div>
												<span class="text-gray-500">upgrades to 100%:</span>
												<span class="ml-1 font-bold"
													>{formBoostAmount > 0
														? Math.ceil((100 - formBaseProbability) / formBoostAmount)
														: 0} upgrades</span
												>
											</div>
										</div>

										{#if formEV.isUnderpriced}
											<div class="mt-3 rounded-lg bg-red-100 p-2 text-xs font-bold text-red-700">
												⚠ Users can profit at upgrade level {formEV.bestPlayerLevel} — expected cost ({formEV.bestPlayerCost})
												is below item price ({formPrice}). Consider increasing upgrade costs or
												lowering boost amount.
											</div>
										{/if}

										{#if showDetailedEV}
											<div class="mt-3 max-h-64 overflow-y-auto">
												<table class="w-full text-left text-xs">
													<thead class="sticky top-0 bg-white">
														<tr class="border-b border-gray-300">
															<th class="px-1 py-1">lv</th>
															<th class="px-1 py-1">displayed</th>
															<th class="px-1 py-1">actual</th>
															<th class="px-1 py-1">roll cost</th>
															<th class="px-1 py-1">upgr cost</th>
															<th class="px-1 py-1">E[rolls]</th>
															<th class="px-1 py-1">E[total]</th>
															<th class="px-1 py-1">ratio</th>
														</tr>
													</thead>
													<tbody>
														{#each formEV.results as r}
															<tr class="border-b">
																<td class="px-1 py-1">{r.upgradeLevel}</td>
																<td class="px-1 py-1">{r.effectiveProbability}%</td>
																<td class="px-1 py-1">{r.actualWinChance}%</td>
																<td class="px-1 py-1">{r.rollCost}</td>
																<td class="px-1 py-1">{r.upgradeCostCumulative}</td>
																<td class="px-1 py-1">{r.expectedRolls}</td>
																<td
																	class="px-1 py-1 {r.evRatio < 1 ? 'font-bold text-red-600' : ''}"
																	>{r.expectedTotalCost}</td
																>
																<td
																	class="px-1 py-1 {r.evRatio < 1 ? 'font-bold text-red-600' : ''}"
																	>{r.evRatio}×</td
																>
															</tr>
														{/each}
													</tbody>
												</table>
											</div>
										{/if}
									</div>
								{/if}
							</div>

							<div class="mt-6 flex gap-3">
								<button
									onclick={closeModal}
									disabled={saving}
									class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
									>{$t.common.cancel}</button
								>
								<button
									onclick={handleSubmit}
									disabled={saving}
									class="flex-1 cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
									>{saving
										? $t.common.saving
										: editingItem
											? $t.common.save
											: $t.common.create}</button
								>
							</div>
						</div>
					</div>
				{/if}

{#if deleteConfirmId}
	{@const deleteItem = items.find((i) => i.id === deleteConfirmId)}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (deleteConfirmId = null)}
		onkeydown={(e) => e.key === 'Escape' && (deleteConfirmId = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">delete item</h2>
			<p class="mb-6 text-gray-600">
				are you sure you want to delete <span class="font-bold"
					>{deleteItem?.name ?? 'this item'}</span
				>? this cannot be undone.
			</p>
			<div class="flex gap-3">
				<button
					onclick={() => (deleteConfirmId = null)}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
				>
					cancel
				</button>
				<button
					onclick={() => confirmDelete()}
					class="flex-1 cursor-pointer rounded-full border-4 border-red-600 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed"
				>
					delete
				</button>
			</div>
		</div>
	</div>
{/if}

{#if errorModal}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (errorModal = null)}
		onkeydown={(e) => e.key === 'Escape' && (errorModal = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">notice</h2>
			<p class="mb-6 text-gray-600">{errorModal}</p>
			<button
				onclick={() => (errorModal = null)}
				class="w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800"
			>
				ok
			</button>
		</div>
	</div>
{/if}

{#if showGachaponModal}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && closeGachaponModal()}
		onkeydown={(e) => e.key === 'Escape' && closeGachaponModal()}
		role="dialog"
		tabindex="-1"
	>
		<div class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border-4 border-black bg-white p-6">
			<div class="mb-6 flex items-center justify-between">
				<h2 class="text-2xl font-bold">{editingGachapon ? 'edit gachapon' : 'new gachapon'}</h2>
				<button
					onclick={closeGachaponModal}
					class="cursor-pointer rounded-lg p-2 transition-colors hover:bg-gray-100"
				>
					<X size={20} />
				</button>
			</div>

			{#if gachaError}
				<div class="mb-4 rounded-lg border-2 border-red-600 bg-red-50 p-3 text-sm text-red-600">
					{gachaError}
				</div>
			{/if}

			<div class="space-y-4">
				<div>
					<label for="gacha-name" class="mb-1 block text-sm font-bold">name</label>
					<input
						id="gacha-name"
						type="text"
						bind:value={gachaName}
						placeholder="Shirt Gachapon"
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
				</div>

				<div>
					<span class="mb-1 block text-sm font-bold">image</span>
					<div class="flex items-center gap-3">
						{#if gachaImage}
							<img
								src={gachaImage}
								alt=""
								class="h-16 w-16 shrink-0 rounded-lg border-2 border-black object-cover"
							/>
						{/if}
						<label
							class="flex cursor-pointer items-center gap-2 rounded-lg border-2 border-black px-4 py-2 font-bold transition-all hover:border-dashed {gachaUploadingImage
								? 'opacity-50'
								: ''}"
						>
							<Upload size={16} />
							{gachaUploadingImage ? 'uploading…' : gachaImage ? 'replace' : 'upload'}
							<input
								type="file"
								accept="image/*"
								onchange={handleGachaImageUpload}
								disabled={gachaUploadingImage}
								class="hidden"
							/>
						</label>
					</div>
					<input
						type="text"
						bind:value={gachaImage}
						placeholder="…or paste an image URL"
						class="mt-2 w-full rounded-lg border-2 border-black px-4 py-2 text-sm focus:border-dashed focus:outline-none"
					/>
				</div>

				<div>
					<label for="gacha-description" class="mb-1 block text-sm font-bold">description</label>
					<textarea
						id="gacha-description"
						bind:value={gachaDescription}
						rows="2"
						placeholder="one of five shirt designs, guaranteed"
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
				</div>

				<div>
					<label for="gacha-price" class="mb-1 block text-sm font-bold">price (scraps)</label>
					<input
						id="gacha-price"
						type="number"
						bind:value={gachaPrice}
						min="1"
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
					<p class="mt-1 text-xs text-gray-500">
						should be a bit above the pool's items' normal cost — you're paying for the guarantee
					</p>
				</div>

				<div>
					<span class="mb-1 block text-sm font-bold"
						>items in this gachapon ({gachaSelectedItemIds.size} selected)</span
					>
					<div class="max-h-64 space-y-1 overflow-y-auto rounded-lg border-2 border-black p-2">
						{#each items as item (item.id)}
							<label
								class="flex cursor-pointer items-center gap-2 rounded-lg p-1.5 hover:bg-gray-100 {gachaSelectedItemIds.has(
									item.id
								)
									? 'bg-indigo-50'
									: ''}"
							>
								<input
									type="checkbox"
									checked={gachaSelectedItemIds.has(item.id)}
									onchange={() => toggleGachaItem(item.id)}
									class="cursor-pointer"
								/>
								{#if item.image}
									<img src={item.image} alt="" class="h-8 w-8 rounded object-cover" />
								{/if}
								<span class="flex-1 truncate text-sm">{item.name}</span>
								<span class="text-xs text-gray-500"
									>{isInfiniteStock(item.count) ? '∞' : stockLabel(item.count)}</span
								>
							</label>
						{/each}
					</div>
				</div>

				<button
					onclick={handleGachaponSubmit}
					disabled={gachaSaving}
					class="w-full cursor-pointer rounded-full bg-black px-4 py-3 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
				>
					{gachaSaving ? 'saving…' : editingGachapon ? 'save changes' : 'create gachapon'}
				</button>
			</div>
		</div>
	</div>
{/if}

{#if gachaDeleteConfirmId}
	{@const deleteGachapon = gachapons.find((g) => g.id === gachaDeleteConfirmId)}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (gachaDeleteConfirmId = null)}
		onkeydown={(e) => e.key === 'Escape' && (gachaDeleteConfirmId = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">delete gachapon</h2>
			<p class="mb-6 text-gray-600">
				are you sure you want to delete <span class="font-bold"
					>{deleteGachapon?.name ?? 'this gachapon'}</span
				>? this cannot be undone.
			</p>
			<div class="flex gap-3">
				<button
					onclick={() => (gachaDeleteConfirmId = null)}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
				>
					cancel
				</button>
				<button
					onclick={() => confirmDeleteGachapon()}
					class="flex-1 cursor-pointer rounded-full border-4 border-red-600 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed"
				>
					delete
				</button>
			</div>
		</div>
	</div>
{/if}
