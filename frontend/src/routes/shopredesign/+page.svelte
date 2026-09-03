<script lang="ts">
	// SANDBOX PAGE — /shopredesign
	// Playground for trying out shop layout ideas. Pulls the same live shop items as
	// /shop (fetchShopItems), so anything uploaded in admin shows up here too.
	// Not linked in the navbar on purpose. Delete or fold into /shop once an idea sticks.
	import { onMount } from 'svelte';
	import HeartButton from '$lib/components/HeartButton.svelte';
	import ShopItemModal from '$lib/components/ShopItemModal.svelte';
	import { getUser } from '$lib/auth-client';
	import { Spool, Clock, Sparkles, Bookmark } from '@lucide/svelte';
	import {
		shopItemsStore,
		shopLoading,
		fetchShopItems,
		updateShopItemHeart,
		type ShopItem
	} from '$lib/stores';
	import { API_URL } from '$lib/config';

	const PHI = (1 + Math.sqrt(5)) / 2;
	const MULTIPLIER = 10;

	type Mode = 'featured' | 'sections' | 'rotating';
	let mode = $state<Mode>('featured');
	let selectedItem = $state<ShopItem | null>(null);

	// how many items the simulated weekly rotation surfaces at once
	let rotationSize = $state(6);
	// lets you scrub the "current week" to preview future rotations
	let weekOffset = $state(0);

	// --- save-to-grow-shop mechanic (localStorage-backed sandbox) ---
	let slotsPerWeek = $state(2);
	let maxSaves = $state(20);
	// item ids the user has locked into their permanent personal shop
	let savedIds = $state<number[]>([]);
	// week number -> ids saved during that week (so undo returns the slot)
	let saveLog = $state<Record<number, number[]>>({});

	const LS_KEY = 'shopredesign:saves:v1';

	function loadSaves() {
		try {
			const raw = localStorage.getItem(LS_KEY);
			if (!raw) return;
			const parsed = JSON.parse(raw);
			savedIds = Array.isArray(parsed.savedIds) ? parsed.savedIds : [];
			saveLog = parsed.saveLog && typeof parsed.saveLog === 'object' ? parsed.saveLog : {};
		} catch {
			/* private window / cleared storage — start empty */
		}
	}

	function persistSaves() {
		try {
			localStorage.setItem(LS_KEY, JSON.stringify({ savedIds, saveLog }));
		} catch {
			/* ignore */
		}
	}

	function estimateHours(scraps: number): number {
		return Math.round((scraps / (PHI * MULTIPLIER)) * 10) / 10;
	}

	function getItemRollCost(item: ShopItem): number {
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

	function probBg(p: number): string {
		if (p >= 70) return 'bg-green-100 text-green-700';
		if (p >= 40) return 'bg-yellow-100 text-yellow-700';
		return 'bg-red-100 text-red-700';
	}

	const inStock = $derived($shopItemsStore.filter((i) => i.count > 0));

	// ---- Featured ----
	const featured = $derived(
		[...inStock].sort((a, b) => b.heartCount - a.heartCount).slice(0, 4)
	);
	const rest = $derived(inStock.filter((i) => !featured.some((f) => f.id === i.id)));

	// ---- Sections ----
	const sections = $derived.by(() => {
		const map = new Map<string, ShopItem[]>();
		for (const item of inStock) {
			const cats = item.category
				.split(',')
				.map((c) => c.trim())
				.filter(Boolean);
			const keys = cats.length ? cats : ['misc'];
			for (const k of keys) {
				if (!map.has(k)) map.set(k, []);
				map.get(k)!.push(item);
			}
		}
		return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]));
	});

	// ---- Rotating (deterministic per week, seeded shuffle) ----
	function currentWeek(): number {
		const epoch = Date.UTC(2026, 0, 5); // a Monday
		return Math.floor((Date.now() - epoch) / (7 * 864e5)) + weekOffset;
	}

	function seededShuffle<T>(arr: T[], seed: number): T[] {
		const out = [...arr];
		let s = seed * 2654435761;
		for (let i = out.length - 1; i > 0; i--) {
			s = (s * 1103515245 + 12345) & 0x7fffffff;
			const j = s % (i + 1);
			[out[i], out[j]] = [out[j], out[i]];
		}
		return out;
	}

	const rotating = $derived(seededShuffle(inStock, currentWeek()).slice(0, rotationSize));

	// your permanent personal shop — saved items, looked up from the full catalog
	// (so a saved item still shows even after it rotates out or sells out)
	const savedItems = $derived(
		savedIds
			.map((id) => $shopItemsStore.find((i) => i.id === id))
			.filter((i): i is ShopItem => !!i)
	);
	// items not in this week's rotation and not saved — you can't touch these
	const rotatingRest = $derived(
		inStock.filter((i) => !rotating.some((r) => r.id === i.id) && !savedIds.includes(i.id))
	);

	const slotsUsedThisWeek = $derived((saveLog[currentWeek()] ?? []).length);
	const slotsLeft = $derived(Math.max(0, slotsPerWeek - slotsUsedThisWeek));
	const atMaxSaves = $derived(savedIds.length >= maxSaves);

	function isSaved(id: number) {
		return savedIds.includes(id);
	}

	function saveItem(id: number) {
		if (isSaved(id) || slotsLeft <= 0 || atMaxSaves) return;
		const wk = currentWeek();
		savedIds = [...savedIds, id];
		saveLog = { ...saveLog, [wk]: [...(saveLog[wk] ?? []), id] };
		persistSaves();
	}

	function unsaveItem(id: number) {
		savedIds = savedIds.filter((x) => x !== id);
		// give the slot back for whichever week it was claimed in
		const next: Record<number, number[]> = {};
		for (const [wk, ids] of Object.entries(saveLog)) {
			const kept = ids.filter((x) => x !== id);
			if (kept.length) next[Number(wk)] = kept;
		}
		saveLog = next;
		persistSaves();
	}

	function resetSaves() {
		savedIds = [];
		saveLog = {};
		persistSaves();
	}

	async function toggleHeart(itemId: number) {
		try {
			const res = await fetch(`${API_URL}/shop/items/${itemId}/heart`, {
				method: 'POST',
				credentials: 'include'
			});
			if (res.ok) {
				const data = await res.json();
				updateShopItemHeart(itemId, data.hearted, data.heartCount);
			}
		} catch (e) {
			console.error('heart toggle failed', e);
		}
	}

	function closeModalAndRefresh() {
		selectedItem = null;
		fetchShopItems(true);
	}

	onMount(async () => {
		loadSaves();
		await getUser();
		fetchShopItems();
	});
</script>

<svelte:head>
	<title>shop redesign sandbox - scraps</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-2 flex items-center gap-2">
		<Sparkles size={28} />
		<h1 class="text-4xl font-bold md:text-5xl">shop redesign</h1>
	</div>
	<p class="mb-8 text-lg text-gray-600">
		Sandbox for layout ideas. Live items from <code>/shop</code> — uploads show up here too.
	</p>

	<!-- Mode switcher -->
	<div class="mb-6 flex flex-wrap gap-2">
		{#each [['featured', 'Featured + grid'], ['sections', 'Sections by category'], ['rotating', 'Weekly rotation']] as [value, label]}
			<button
				onclick={() => (mode = value as Mode)}
				class="cursor-pointer rounded-full border-4 border-black px-4 py-2 text-sm font-bold transition-all {mode ===
				value
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{label}
			</button>
		{/each}
	</div>

	{#if mode === 'rotating'}
		<div
			class="mb-6 flex flex-wrap items-center gap-x-6 gap-y-3 rounded-xl border-2 border-dashed border-black p-4 text-sm"
		>
			<label class="flex items-center gap-2 font-bold">
				items in rotation
				<input type="range" min="3" max="12" bind:value={rotationSize} />
				<span class="w-6">{rotationSize}</span>
			</label>
			<label class="flex items-center gap-2 font-bold">
				week
				<button class="rounded border-2 border-black px-2" onclick={() => weekOffset--}>-</button>
				<span class="w-8 text-center">{weekOffset === 0 ? 'now' : `+${weekOffset}`}</span>
				<button class="rounded border-2 border-black px-2" onclick={() => weekOffset++}>+</button>
			</label>
			<label class="flex items-center gap-2 font-bold">
				save slots / week
				<input type="range" min="1" max="4" bind:value={slotsPerWeek} />
				<span class="w-6">{slotsPerWeek}</span>
			</label>
			<label class="flex items-center gap-2 font-bold">
				max saves
				<input type="range" min="5" max="40" step="5" bind:value={maxSaves} />
				<span class="w-6">{maxSaves}</span>
			</label>
			<div class="flex items-center gap-3">
				<span class="rounded-full bg-black px-3 py-1 font-bold text-white">
					{slotsLeft}/{slotsPerWeek} slots left this week
				</span>
				<span class="text-gray-600">{savedIds.length}/{maxSaves} saved</span>
				{#if savedIds.length > 0}
					<button
						onclick={resetSaves}
						class="rounded-full border-2 border-red-600 px-3 py-1 font-bold text-red-600 hover:border-dashed"
					>
						clear
					</button>
				{/if}
			</div>
		</div>
	{/if}

	{#if $shopLoading}
		<div class="py-12 text-center text-gray-600">loading items…</div>
	{:else if inStock.length === 0}
		<div class="py-12 text-center text-gray-600">no items in stock</div>
	{:else if mode === 'featured'}
		<h2 class="mb-4 text-2xl font-bold">✨ Featured</h2>
		<div class="mb-12 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
			{#each featured as item (item.id)}
				{@render bigCard(item)}
			{/each}
		</div>
		<h2 class="mb-4 text-2xl font-bold">Everything else</h2>
		<div class="grid grid-cols-1 gap-6 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
			{#each rest as item (item.id)}
				{@render card(item)}
			{/each}
		</div>
	{:else if mode === 'sections'}
		{#each sections as [name, items] (name)}
			<h2 class="mb-4 text-2xl font-bold capitalize">{name}</h2>
			<div class="mb-12 grid grid-cols-1 gap-6 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
				{#each items as item (item.id)}
					{@render card(item)}
				{/each}
			</div>
		{/each}
	{:else if mode === 'rotating'}
		<div class="mb-2 flex items-center justify-between">
			<h2 class="text-2xl font-bold">🎲 This week's picks</h2>
		</div>
		<p class="mb-4 text-sm text-gray-600">
			Save the ones you want to keep forever — {slotsLeft} slot{slotsLeft === 1 ? '' : 's'} left this week.
		</p>
		<div class="mb-12 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
			{#each rotating as item (item.id)}
				{@render bigCard(item, true)}
			{/each}
		</div>

		<h2 class="mb-1 text-2xl font-bold">🏪 My shop</h2>
		<p class="mb-4 text-sm text-gray-600">
			{savedItems.length === 0
				? 'Nothing saved yet. Items you save stay here permanently, even after they rotate out.'
				: `${savedItems.length} item${savedItems.length === 1 ? '' : 's'} — always available to you.`}
		</p>
		{#if savedItems.length > 0}
			<div class="mb-12 grid grid-cols-1 gap-6 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
				{#each savedItems as item (item.id)}
					{@render savedCard(item)}
				{/each}
			</div>
		{/if}

		{#if rotatingRest.length}
			<h2 class="mb-4 text-2xl font-bold text-gray-400">Not in rotation</h2>
			<div class="grid grid-cols-1 gap-6 opacity-50 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
				{#each rotatingRest as item (item.id)}
					{@render card(item)}
				{/each}
			</div>
		{/if}
	{/if}
</div>

{#snippet card(item: ShopItem)}
	{@const rollCost = getItemRollCost(item)}
	<button
		onclick={() => (selectedItem = item)}
		class="relative cursor-pointer overflow-hidden rounded-2xl border-4 border-black p-4 text-left transition-all hover:border-dashed"
	>
		<div class="relative">
			<img src={item.image} alt={item.name} class="mb-4 h-32 w-full object-contain" />
			<span
				class="absolute top-0 right-0 rounded-full px-2 py-1 text-xs font-bold {probBg(
					item.effectiveProbability
				)}"
			>
				{item.effectiveProbability.toFixed(0)}%
			</span>
		</div>
		<h3 class="mb-1 truncate text-xl font-bold">{item.name}</h3>
		<p class="mb-2 line-clamp-2 text-sm text-gray-600">{item.description}</p>
		<span class="flex items-center gap-1 text-lg font-bold"><Spool size={18} />{rollCost}</span>
		<span class="mt-1 flex items-center gap-1 text-xs text-gray-500"
			><Clock size={14} />~{estimateHours(rollCost)}h</span
		>
		<div class="mt-3 flex items-center justify-between">
			<span class="text-xs text-gray-500">{item.count} left</span>
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
{/snippet}

{#snippet bigCard(item: ShopItem, showSave = false)}
	{@const rollCost = getItemRollCost(item)}
	<div
		class="relative overflow-hidden rounded-2xl border-4 border-black bg-yellow-50 transition-all {isSaved(
			item.id
		)
			? 'ring-4 ring-green-400'
			: ''}"
	>
		<button onclick={() => (selectedItem = item)} class="w-full cursor-pointer p-5 text-left hover:opacity-90">
			<div class="relative">
				<img src={item.image} alt={item.name} class="mb-4 h-40 w-full object-contain" />
				<span
					class="absolute top-0 right-0 rounded-full px-2 py-1 text-xs font-bold {probBg(
						item.effectiveProbability
					)}"
				>
					{item.effectiveProbability.toFixed(0)}% chance
				</span>
			</div>
			<h3 class="mb-1 truncate text-2xl font-bold">{item.name}</h3>
			<p class="mb-3 line-clamp-2 text-sm text-gray-600">{item.description}</p>
			<div class="flex items-end justify-between">
				<div>
					<span class="flex items-center gap-1 text-xl font-bold"><Spool size={20} />{rollCost}</span>
					<span class="mt-1 flex items-center gap-1 text-xs text-gray-500"
						><Clock size={14} />~{estimateHours(rollCost)}h · {item.count} left</span
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
		{#if showSave}
			<div class="border-t-2 border-black px-5 py-3">
				{@render saveControl(item)}
			</div>
		{/if}
	</div>
{/snippet}

{#snippet saveControl(item: ShopItem)}
	{#if isSaved(item.id)}
		<div class="flex items-center justify-between text-sm font-bold">
			<span class="flex items-center gap-1 text-green-700"><Bookmark size={16} /> in your shop</span>
			<button
				onclick={() => unsaveItem(item.id)}
				class="cursor-pointer text-xs text-gray-500 underline hover:text-red-600"
			>
				remove
			</button>
		</div>
	{:else if slotsLeft > 0 && !atMaxSaves}
		<button
			onclick={() => saveItem(item.id)}
			class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-2 text-sm font-bold text-white transition-all hover:bg-gray-800"
		>
			<Bookmark size={16} /> Save to my shop
		</button>
	{:else}
		<p class="text-center text-xs font-bold text-gray-400">
			{atMaxSaves ? 'shop full' : 'no slots left this week'}
		</p>
	{/if}
{/snippet}

{#snippet savedCard(item: ShopItem)}
	{@const rollCost = getItemRollCost(item)}
	<div class="relative overflow-hidden rounded-2xl border-4 border-green-500">
		<button
			onclick={() => (selectedItem = item)}
			class="w-full cursor-pointer p-4 text-left hover:opacity-90 {item.count === 0
				? 'opacity-50 grayscale'
				: ''}"
		>
			<div class="relative">
				<img src={item.image} alt={item.name} class="mb-4 h-32 w-full object-contain" />
				<span
					class="absolute top-0 right-0 rounded-full px-2 py-1 text-xs font-bold {probBg(
						item.effectiveProbability
					)}"
				>
					{item.effectiveProbability.toFixed(0)}%
				</span>
			</div>
			<h3 class="mb-1 truncate text-xl font-bold">{item.name}</h3>
			<span class="flex items-center gap-1 text-lg font-bold"><Spool size={18} />{rollCost}</span>
			<span class="text-xs text-gray-500">{item.count === 0 ? 'restocking' : `${item.count} left`}</span>
		</button>
		<button
			onclick={() => unsaveItem(item.id)}
			class="w-full cursor-pointer border-t-2 border-green-500 py-2 text-xs font-bold text-gray-500 hover:text-red-600"
		>
			remove from shop
		</button>
	</div>
{/snippet}

{#if selectedItem}
	<ShopItemModal
		item={selectedItem}
		onClose={() => (selectedItem = null)}
		onTryLuck={closeModalAndRefresh}
		onConsolation={closeModalAndRefresh}
		onPurchase={closeModalAndRefresh}
	/>
{/if}
