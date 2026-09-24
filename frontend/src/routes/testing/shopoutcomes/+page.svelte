<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { getUser } from '$lib/auth-client';
	import { shopItemsStore, fetchShopItems, type ShopItem } from '$lib/stores';
	import { t } from '$lib/i18n';
	import GachaponPull from '$lib/components/GachaponPull.svelte';
	import AddressSelectModal from '$lib/components/AddressSelectModal.svelte';
	import RollStrip from '$lib/components/RollStrip.svelte';
	import UpgradeCheckmark from '$lib/components/UpgradeCheckmark.svelte';
	import { computeRollThreshold } from '$lib/utils';
	import { Trophy, Frown, Wrench, Truck, Dices, Sparkles, RotateCcw } from '@lucide/svelte';

	// SANDBOX PAGE: /testing/shopoutcomes
	// Every reveal/animation/modal that plays after a shop action, on demand:
	// winning a roll, losing one (consolation roll), pulling a gachapon,
	// upgrading in the refinery, and fulfilling an order (shipping address) after
	// any of those. Real prize names/images come from the live /shop/items list
	// (read-only); nothing here writes a real order or spends real scraps — the
	// one write call AddressSelectModal makes is intercepted below and faked.

	let pool = $derived($shopItemsStore.filter((i) => i.count !== 0));
	function randomItem(): ShopItem | null {
		if (pool.length === 0) return null;
		return pool[Math.floor(Math.random() * pool.length)];
	}

	let history = $state<string[]>([]);
	function log(line: string) {
		history = [line, ...history].slice(0, 15);
	}

	// Only the write call AddressSelectModal makes is faked (POST .../address).
	// The GET for saved addresses hits the real endpoint so the form still
	// pre-fills with your actual address, same as production.
	let restoreFetch: (() => void) | null = null;
	function installAddressSubmitMock() {
		const original = window.fetch.bind(window);
		window.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
			const url =
				typeof input === 'string' ? input : input instanceof Request ? input.url : input.toString();
			if (init?.method === 'POST' && /\/shop\/orders\/[^/]+\/address$/.test(url)) {
				await new Promise((r) => setTimeout(r, 400));
				return new Response(JSON.stringify({ success: true }), {
					status: 200,
					headers: { 'Content-Type': 'application/json' }
				});
			}
			return original(input as RequestInfo, init);
		}) as typeof window.fetch;
		restoreFetch = () => {
			window.fetch = original;
		};
	}

	// ---- fulfillment (shipping address) step: shared tail of every scenario ----
	// Prod shows the same plain "congratulations, you won X" modal here
	// regardless of whether the win came from a roll, a gachapon, or a claimed
	// consolation roll (see shop/+page.svelte: finishConsolationReveal() just
	// reuses winningItemName/winningOrderId, no special header) — so this
	// never varies by scenario either.
	let mockOrderCounter = 90_000_000;
	let addressPrompt = $state<{ orderId: number; itemName: string } | null>(null);

	function openFulfillment(itemName: string) {
		mockOrderCounter += 1;
		addressPrompt = { orderId: mockOrderCounter, itemName };
	}

	function finishFulfillment() {
		log(`fulfilled: shipping address saved for "${addressPrompt?.itemName}"`);
		addressPrompt = null;
	}

	// ---- winning a roll (no reveal animation in prod: straight to address) ----
	function simulateWin() {
		const item = randomItem();
		const name = item?.name ?? 'Mystery Prize';
		log(`won a roll: ${name}`);
		openFulfillment(name);
	}

	// ---- losing a roll -> consolation roll ----
	let consolationPromptOpen = $state(false);
	let consolationRolled = $state(0);
	let consolationNeeded = $state(0);
	let consolationCreditsMock = $state(0);
	let claimingConsolation = $state(false);
	let consolationReveal = $state<{ itemName: string; itemImage: string | null } | null>(null);

	function simulateLoss() {
		consolationNeeded = Math.floor(Math.random() * 30) + 10;
		consolationRolled = consolationNeeded + Math.floor(Math.random() * 40) + 1;
		consolationCreditsMock += 1;
		consolationPromptOpen = true;
		log(
			`lost a roll (rolled ${consolationRolled}, needed ${consolationNeeded}) → consolation roll credited`
		);
	}

	function claimConsolation() {
		claimingConsolation = true;
		setTimeout(() => {
			claimingConsolation = false;
			consolationPromptOpen = false;
			consolationCreditsMock = Math.max(0, consolationCreditsMock - 1);
			const item = randomItem();
			consolationReveal = {
				itemName: item?.name ?? 'Consolation Prize',
				itemImage: item?.image ?? null
			};
		}, 500);
	}

	function saveConsolationForLater() {
		consolationPromptOpen = false;
		log('consolation roll saved for later (banner should show below)');
	}

	function finishConsolationReveal() {
		const name = consolationReveal?.itemName ?? 'Consolation Prize';
		consolationReveal = null;
		log(`consolation roll claimed: ${name}`);
		openFulfillment(name);
	}

	// ---- gachapon pull ----
	let gachaponPulling = $state(false);
	let gachaponReveal = $state<{
		itemName: string;
		itemImage: string | null;
		gachaponName: string;
	} | null>(null);

	function simulateGachaponPull() {
		if (gachaponPulling || gachaponReveal) return;
		gachaponPulling = true;
		setTimeout(() => {
			gachaponPulling = false;
			const item = randomItem();
			gachaponReveal = {
				itemName: item?.name ?? 'Capsule Prize',
				itemImage: item?.image ?? null,
				gachaponName: 'Test Gachapon'
			};
		}, 400);
	}

	function finishGachaponReveal() {
		const name = gachaponReveal?.itemName ?? 'Capsule Prize';
		gachaponReveal = null;
		log(`gachapon win: ${name}`);
		openFulfillment(name);
	}

	let rollPreview = $state<{
		itemName: string;
		finalNumber: number;
		winThreshold: number;
		won: boolean;
	} | null>(null);

	function spinPreview() {
		if (rollPreview) return;
		const item = randomItem();
		const effectiveProbability = Math.floor(Math.random() * 60) + 10;
		const winThreshold = computeRollThreshold(effectiveProbability);
		const finalNumber = Math.floor(Math.random() * 100) + 1;
		rollPreview = {
			itemName: item?.name ?? 'Test Item',
			finalNumber,
			winThreshold,
			won: finalNumber <= winThreshold
		};
	}

	function finishSpinPreview() {
		if (!rollPreview) return;
		log(
			`rolled ${rollPreview.finalNumber} (win ≤ ${rollPreview.winThreshold}) → ${rollPreview.won ? 'won' : 'lost'}`
		);
		rollPreview = null;
	}

	// ---- refinery upgrade (no modal in prod: button label + numbers change) ----
	const REFINERY_BOOST_STEP = 5;
	const REFINERY_MAX_BOOST = 40;
	let refineryBoost = $state(0);
	let refineryUpgrading = $state(false);
	let refineryMaxed = $derived(refineryBoost >= REFINERY_MAX_BOOST);

	let refineryCheck = $state(false);

	function simulateUpgrade() {
		if (refineryUpgrading || refineryMaxed) return;
		refineryUpgrading = true;
		setTimeout(() => {
			refineryBoost = Math.min(REFINERY_MAX_BOOST, refineryBoost + REFINERY_BOOST_STEP);
			refineryUpgrading = false;
			refineryCheck = true;
			log(`refinery upgrade: +${REFINERY_BOOST_STEP}% (now +${refineryBoost}%)`);
		}, 500);
	}

	function resetRefinery() {
		refineryBoost = 0;
	}

	function resetAll() {
		history = [];
		consolationCreditsMock = 0;
		refineryBoost = 0;
	}

	onMount(async () => {
		installAddressSubmitMock();
		await getUser();
		fetchShopItems();
	});

	onDestroy(() => {
		restoreFetch?.();
	});
</script>

<svelte:head>
	<title>shop outcomes sandbox - scraps</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-2 flex items-center gap-2">
		<Sparkles size={28} />
		<h1 class="text-4xl font-bold md:text-5xl">shop outcomes</h1>
	</div>
	<p class="mb-8 text-lg text-gray-600">
		Every reveal/modal that plays after a shop action, on a button. Prize names/images come from the
		live shop; nothing here spends real scraps or writes a real order.
	</p>

	<div class="grid gap-4 sm:grid-cols-2">
		<div class="rounded-2xl border-4 border-black p-4">
			<h2 class="mb-1 flex items-center gap-2 text-lg font-bold">
				<Trophy size={20} /> win a roll
			</h2>
			<p class="mb-3 text-sm text-gray-600">
				No reveal in prod: goes straight to the shipping-address step.
			</p>
			<button
				onclick={simulateWin}
				class="w-full cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800"
			>
				win a roll
			</button>
		</div>

		<div class="rounded-2xl border-4 border-black p-4 sm:col-span-2">
			<h2 class="mb-1 flex items-center gap-2 text-lg font-bold">
				<Dices size={20} /> roll strip alone
			</h2>
			<p class="mb-3 text-sm text-gray-600">
				Random roll and threshold each click, no fulfillment step after.
			</p>
			<button
				onclick={spinPreview}
				disabled={!!rollPreview}
				class="w-full cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50 sm:w-auto"
			>
				spin
			</button>
		</div>

		<div class="rounded-2xl border-4 border-black p-4">
			<h2 class="mb-1 flex items-center gap-2 text-lg font-bold">
				<Frown size={20} /> lose a roll
			</h2>
			<p class="mb-3 text-sm text-gray-600">
				Consolation prompt → claim now (roll reveal → address) or save for later (banner below).
			</p>
			<button
				onclick={simulateLoss}
				disabled={consolationPromptOpen}
				class="w-full cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
			>
				lose a roll
			</button>
		</div>

		<div class="rounded-2xl border-4 border-black p-4">
			<h2 class="mb-1 flex items-center gap-2 text-lg font-bold">
				<Dices size={20} /> pull a gachapon
			</h2>
			<p class="mb-3 text-sm text-gray-600">
				Capsule reveal → shipping-address step, same as prod.
			</p>
			<button
				onclick={simulateGachaponPull}
				disabled={gachaponPulling || !!gachaponReveal}
				class="w-full cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
			>
				{gachaponPulling ? 'pulling…' : 'pull a gachapon'}
			</button>
		</div>

		<div class="rounded-2xl border-4 border-black p-4">
			<h2 class="mb-1 flex items-center gap-2 text-lg font-bold">
				<Wrench size={20} /> refinery upgrade
			</h2>
			<p class="mb-3 text-sm text-gray-600">
				No modal in prod: button label + numbers change in place.
			</p>
			<div class="mb-3 flex items-center justify-between rounded-lg border-2 border-black p-3">
				<span class="font-bold">boost: +{refineryBoost}%</span>
				{#if refineryBoost > 0}
					<button onclick={resetRefinery} class="cursor-pointer text-xs text-gray-500 underline">
						reset
					</button>
				{/if}
			</div>
			<div class="relative">
				<button
					onclick={simulateUpgrade}
					disabled={refineryUpgrading || refineryMaxed}
					class="w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
				>
					{refineryMaxed
						? $t.refinery.maxed
						: refineryUpgrading
							? $t.refinery.upgrading
							: `+${REFINERY_BOOST_STEP}% upgrade`}
				</button>
				{#if refineryCheck}
					<UpgradeCheckmark onDone={() => (refineryCheck = false)} />
				{/if}
			</div>
		</div>

		<div class="rounded-2xl border-4 border-black p-4 sm:col-span-2">
			<h2 class="mb-1 flex items-center gap-2 text-lg font-bold">
				<Truck size={20} /> fulfillment (shipping address) alone
			</h2>
			<p class="mb-3 text-sm text-gray-600">
				Open just the address step on its own, without a win/loss leading into it.
			</p>
			<button
				onclick={() => openFulfillment('Test Item')}
				class="w-full cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all hover:border-dashed sm:w-auto"
			>
				open fulfillment step
			</button>
		</div>
	</div>

	{#if consolationCreditsMock > 0 && !consolationPromptOpen}
		<div
			class="mt-8 flex flex-wrap items-center justify-between gap-3 rounded-2xl border-4 border-yellow-500 bg-yellow-50 p-4"
		>
			<div>
				<p class="font-bold text-yellow-800">
					{consolationCreditsMock === 1
						? $t.shop.oneConsolationWaiting
						: $t.shop.manyConsolationsWaiting.replace('{count}', String(consolationCreditsMock))}
				</p>
				<p class="text-sm text-yellow-700">{$t.shop.consolationWaitingHint}</p>
			</div>
			<button
				onclick={claimConsolation}
				disabled={claimingConsolation}
				class="cursor-pointer rounded-full border-4 border-black bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
			>
				{claimingConsolation ? $t.shop.rollingConsolation : $t.shop.rollConsolation}
			</button>
		</div>
	{/if}

	{#if history.length > 0}
		<div class="mt-8 flex items-center justify-between">
			<h2 class="text-xl font-bold">log</h2>
			<button
				onclick={resetAll}
				class="flex cursor-pointer items-center gap-1 text-sm text-gray-500 underline hover:text-black"
			>
				<RotateCcw size={14} /> reset everything
			</button>
		</div>
		<ul class="mt-2 space-y-1 text-sm text-gray-600">
			{#each history as h, i (i)}
				<li>{h}</li>
			{/each}
		</ul>
	{/if}
</div>

{#if consolationPromptOpen}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && saveConsolationForLater()}
		onkeydown={(e) => e.key === 'Escape' && saveConsolationForLater()}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6 text-center">
			<div class="mb-4 rounded-xl border-2 border-yellow-400 bg-yellow-50 p-4">
				<p class="font-bold text-yellow-800">{$t.shop.betterLuckNextTime}</p>
				<p class="mt-1 text-sm text-yellow-700">
					{$t.shop.youRolledButNeeded
						.replace('{rolled}', String(consolationRolled))
						.replace('{needed}', String(consolationNeeded))}
				</p>
				<p class="mt-2 text-sm text-yellow-700">{$t.shop.consolationMessage}</p>
			</div>
			<div class="flex flex-col gap-2">
				<button
					onclick={claimConsolation}
					disabled={claimingConsolation}
					class="cursor-pointer rounded-full border-4 border-black bg-black px-6 py-3 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
				>
					{claimingConsolation ? $t.shop.rollingConsolation : $t.shop.rollConsolation}
				</button>
				<button
					onclick={saveConsolationForLater}
					disabled={claimingConsolation}
					class="cursor-pointer rounded-full border-4 border-black px-6 py-2 font-bold transition-all hover:border-dashed disabled:opacity-50"
				>
					{$t.shop.rollConsolationLater}
				</button>
			</div>
		</div>
	</div>
{/if}

{#if consolationReveal}
	<GachaponPull
		itemName={consolationReveal.itemName}
		itemImage={consolationReveal.itemImage}
		gachaponName={$t.shop.consolationRollTitle}
		onDone={finishConsolationReveal}
	/>
{/if}

{#if gachaponReveal}
	<GachaponPull
		itemName={gachaponReveal.itemName}
		itemImage={gachaponReveal.itemImage}
		gachaponName={gachaponReveal.gachaponName}
		onDone={finishGachaponReveal}
	/>
{/if}

{#if rollPreview}
	<RollStrip
		itemName={rollPreview.itemName}
		finalNumber={rollPreview.finalNumber}
		winThreshold={rollPreview.winThreshold}
		won={rollPreview.won}
		onDone={finishSpinPreview}
	/>
{/if}

{#if addressPrompt}
	<AddressSelectModal
		orderId={addressPrompt.orderId}
		itemName={addressPrompt.itemName}
		onClose={() => (addressPrompt = null)}
		onComplete={finishFulfillment}
	/>
{/if}
