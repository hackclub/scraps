<script lang="ts">
	import { X, Spool, Trophy, Heart, ShoppingBag } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { refreshUserScraps, userScrapsStore } from '$lib/auth-client';
	import HeartButton from './HeartButton.svelte';
	import { type ShopItem, updateShopItemHeart } from '$lib/stores';
	import { t } from '$lib/i18n';

	interface LeaderboardUser {
		userId: string;
		username: string;
		avatar: string;
		boostPercent: number;
		effectiveProbability: number;
	}

	interface Buyer {
		userId: string;
		username: string;
		avatar: string;
		purchasedAt: string;
	}

	interface HeartUser {
		userId: string;
		username: string;
		avatar: string;
	}

	let {
		item,
		onClose,
		onTryLuck,
		onConsolation
	}: {
		item: ShopItem;
		onClose: () => void;
		onTryLuck: (orderId: number) => void;
		onConsolation: (orderId: number, rolled: number, needed: number) => void;
	} = $props();

	let activeTab = $state<'leaderboard' | 'wishlist' | 'buyers'>('leaderboard');
	let leaderboard = $state<LeaderboardUser[]>([]);
	let buyers = $state<Buyer[]>([]);
	let heartUsers = $state<HeartUser[]>([]);
	let loadingLeaderboard = $state(false);
	let loadingBuyers = $state(false);
	let loadingHearts = $state(false);
	let tryingLuck = $state(false);
	let showConfirmation = $state(false);
	let localHearted = $state(item.userHearted);
	let localHeartCount = $state(item.heartCount);
	let rollCost = $derived(
		(() => {
			// Prefer server-provided displayRollCost when present (authoritative).
			// Fallback to local computation if the server value is missing for any reason.
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
			const rollCount = item.rollCount ?? 0;
			return Math.round(baseCost * (1 + perRoll * rollCount));
		})()
	);
	let canAfford = $derived($userScrapsStore >= rollCost);
	let alertMessage = $state<string | null>(null);
	let alertType = $state<'error' | 'info'>('info');

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

	async function fetchLeaderboard() {
		loadingLeaderboard = true;
		try {
			const response = await fetch(`${API_URL}/shop/items/${item.id}/leaderboard`, {
				credentials: 'include'
			});
			if (response.ok) {
				leaderboard = await response.json();
			}
		} catch (e) {
			console.error('Failed to fetch leaderboard:', e);
		} finally {
			loadingLeaderboard = false;
		}
	}

	async function fetchBuyers() {
		loadingBuyers = true;
		try {
			const response = await fetch(`${API_URL}/shop/items/${item.id}/buyers`, {
				credentials: 'include'
			});
			if (response.ok) {
				buyers = await response.json();
			}
		} catch (e) {
			console.error('Failed to fetch buyers:', e);
		} finally {
			loadingBuyers = false;
		}
	}

	async function fetchHeartUsers() {
		loadingHearts = true;
		try {
			const response = await fetch(`${API_URL}/shop/items/${item.id}/hearts`, {
				credentials: 'include'
			});
			if (response.ok) {
				heartUsers = await response.json();
			}
		} catch (e) {
			console.error('Failed to fetch heart users:', e);
		} finally {
			loadingHearts = false;
		}
	}

	async function handleToggleHeart() {
		try {
			const response = await fetch(`${API_URL}/shop/items/${item.id}/heart`, {
				method: 'POST',
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				localHearted = data.hearted;
				localHeartCount = data.heartCount;
				// Sync with the store so the shop page updates
				updateShopItemHeart(item.id, localHearted, localHeartCount);
			}
		} catch (e) {
			console.error('Failed to toggle heart:', e);
		}
	}

	async function handleTryLuck() {
		tryingLuck = true;
		try {
			const response = await fetch(`${API_URL}/shop/items/${item.id}/try-luck`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await response.json();

			if (!response.ok || data.error || !data.success) {
				console.error('[SHOP] try-luck error response:', JSON.stringify(data));
				alertType = 'error';
				const parts = [data.error || $t.shop.failedToTryLuck];
				if (data.required !== undefined) parts.push(`need: ${data.required} scraps`);
				if (data.available !== undefined) parts.push(`have: ${data.available} scraps`);
				alertMessage = parts.join(' — ');
				return;
			}

			await refreshUserScraps();
			if (data.won) {
				onTryLuck(data.orderId);
			} else if (data.consolationOrderId) {
				onConsolation(data.consolationOrderId, data.rolled, Math.floor(data.effectiveProbability));
			} else {
				alertType = 'error';
				alertMessage = $t.shop.somethingWentWrong;
			}
		} catch (e) {
			console.error('Failed to try luck:', e);
			alertType = 'error';
			alertMessage = $t.shop.somethingWentWrong;
		} finally {
			tryingLuck = false;
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

	let leaderboardFetched = false;
	let buyersFetched = false;
	let heartsFetched = false;

	$effect(() => {
		if (activeTab === 'leaderboard' && !leaderboardFetched) {
			leaderboardFetched = true;
			fetchLeaderboard();
		} else if (activeTab === 'buyers' && !buyersFetched) {
			buyersFetched = true;
			fetchBuyers();
		} else if (activeTab === 'wishlist' && !heartsFetched) {
			heartsFetched = true;
			fetchHeartUsers();
		}
	});
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
			<h2 class="text-2xl font-bold">{item.name}</h2>
			<button
				onclick={onClose}
				class="cursor-pointer rounded-lg p-1 transition-colors hover:bg-gray-100"
			>
				<X size={24} />
			</button>
		</div>

		<img
			src={item.image}
			alt={item.name}
			class="mb-4 h-48 w-full rounded-lg bg-gray-50 object-contain"
		/>

		<p class="mb-4 text-gray-600">{item.description}</p>

		<div class="mb-4 flex items-center justify-between">
			<div class="flex items-center gap-4">
				<span class="flex items-center gap-1 text-xl font-bold">
					<Spool size={20} />
					{rollCost}
				</span>
				<span class="text-sm text-gray-500">{item.count} {$t.shop.left}</span>
			</div>
			<HeartButton
				count={localHeartCount}
				hearted={localHearted}
				onclick={() => handleToggleHeart()}
			/>
		</div>

		<div class="mb-4 flex flex-wrap gap-2">
			{#each item.category
				.split(',')
				.map((c) => c.trim())
				.filter(Boolean) as cat}
				<span class="rounded-full bg-gray-100 px-2 py-1 text-xs">{cat}</span>
			{/each}
		</div>

		<div
			class="mb-4 rounded-lg border-2 border-black p-4 {getProbabilityBgColor(
				item.effectiveProbability
			)}"
		>
			<p class="mb-2 text-sm font-bold">{$t.shop.yourChance}</p>
			<p class="text-3xl font-bold {getProbabilityColor(item.effectiveProbability)}">
				{item.effectiveProbability.toFixed(1)}%
			</p>
			<div class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-600">
				<span>{$t.shop.base}: {item.baseProbability}%</span>
				<span>{$t.shop.yourBoost}: +{item.userBoostPercent}%</span>
				{#if item.adjustedBaseProbability < item.baseProbability}
					<span class="text-red-500"
						>{$t.shop.previousBuy}: -{item.baseProbability - item.adjustedBaseProbability}%</span
					>
				{/if}
			</div>
		</div>

		<div class="mb-4 flex gap-2">
			<button
				onclick={() => (activeTab = 'leaderboard')}
				class="flex flex-1 cursor-pointer items-center justify-center gap-1 rounded-full border-4 border-black px-3 py-2 font-bold transition-all duration-200 {activeTab ===
				'leaderboard'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				<Trophy size={16} />
				{$t.shop.leaderboard}
			</button>
			<button
				onclick={() => (activeTab = 'wishlist')}
				class="flex flex-1 cursor-pointer items-center justify-center gap-1 rounded-full border-4 border-black px-3 py-2 font-bold transition-all duration-200 {activeTab ===
				'wishlist'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				<Heart size={16} />
				{$t.shop.wishlist} ({localHeartCount})
			</button>
			<button
				onclick={() => (activeTab = 'buyers')}
				class="flex flex-1 cursor-pointer items-center justify-center gap-1 rounded-full border-4 border-black px-3 py-2 font-bold transition-all duration-200 {activeTab ===
				'buyers'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				<ShoppingBag size={16} />
				{$t.shop.buyers}
			</button>
		</div>

		<div class="mb-6 min-h-30 rounded-lg border-2 border-black p-4">
			{#if activeTab === 'leaderboard'}
				{#if loadingLeaderboard}
					<p class="text-center text-gray-500">{$t.common.loading}</p>
				{:else if leaderboard.length === 0}
					<p class="text-center text-gray-500">{$t.shop.noOneHasBoostedYet}</p>
				{:else}
					<div class="space-y-2">
						{#each leaderboard as user, i}
							<div class="flex items-center gap-3">
								<span class="w-6 font-bold">{i + 1}.</span>
								<img src={user.avatar} alt={user.username} class="h-8 w-8 rounded-full" />
								<span class="flex-1 font-medium">{user.username}</span>
								<span class="text-sm {getProbabilityColor(user.effectiveProbability)}">
									{user.effectiveProbability.toFixed(1)}%
								</span>
							</div>
						{/each}
					</div>
				{/if}
			{:else if activeTab === 'wishlist'}
				<div class="text-center">
					<p class="mb-2 text-2xl font-bold">{localHeartCount}</p>
					<p class="mb-4 text-gray-600">{$t.shop.peopleWantThisItem}</p>
					{#if localHearted}
						<p class="mb-4 text-sm font-medium text-green-600">{$t.shop.includingYou}</p>
					{/if}
					{#if loadingHearts}
						<p class="text-sm text-gray-500">{$t.common.loading}</p>
					{:else if heartUsers.length > 0}
						<div class="mt-2 flex flex-wrap justify-center gap-2">
							{#each heartUsers as heartUser, i}
								<div
									class="relative"
									style="animation: float 3s ease-in-out infinite; animation-delay: {i * 0.2}s"
								>
									<img
										src={heartUser.avatar}
										alt={heartUser.username}
										title={heartUser.username}
										class="h-10 w-10 cursor-pointer rounded-full border-2 border-pink-300 shadow-md transition-transform hover:scale-110"
									/>
								</div>
							{/each}
						</div>
					{/if}
				</div>
			{:else if activeTab === 'buyers'}
				{#if loadingBuyers}
					<p class="text-center text-gray-500">{$t.common.loading}</p>
				{:else if buyers.length === 0}
					<p class="text-center text-gray-500">{$t.shop.noOneHasWonYet}</p>
				{:else}
					<div class="space-y-2">
						{#each buyers as buyer}
							<div class="flex items-center gap-3">
								<img src={buyer.avatar} alt={buyer.username} class="h-8 w-8 rounded-full" />
								<span class="flex-1 font-medium">{buyer.username}</span>
								<span class="text-xs text-gray-500">
									{new Date(buyer.purchasedAt).toLocaleDateString()}
								</span>
							</div>
						{/each}
					</div>
				{/if}
			{/if}
		</div>

		{#if item.count === 0}
			<span
				class="block w-full cursor-not-allowed rounded-full border-4 border-dashed border-gray-300 px-4 py-3 text-center text-lg font-bold text-gray-400"
			>
				{$t.shop.soldOut}
			</span>
		{:else}
			<button
				onclick={() => (showConfirmation = true)}
				disabled={tryingLuck || !canAfford}
				class="w-full cursor-pointer rounded-full bg-black px-4 py-3 text-lg font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
			>
				{#if !canAfford}
					{$t.shop.notEnoughScraps}
				{:else}
					{$t.shop.tryYourLuck}
				{/if}
			</button>
		{/if}
	</div>

	{#if showConfirmation}
		<div
			class="fixed inset-0 z-60 flex items-center justify-center bg-black/50 p-4"
			onclick={(e) => e.target === e.currentTarget && (showConfirmation = false)}
			onkeydown={(e) => e.key === 'Escape' && (showConfirmation = false)}
			role="dialog"
			tabindex="-1"
		>
			<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
				<h2 class="mb-4 text-2xl font-bold">{$t.shop.confirmTryYourLuck}</h2>
				<p class="mb-6 text-gray-600">
					{$t.shop.confirmTryLuckMessage} <strong>{rollCost} {$t.common.scraps}</strong>.
					<span class="mt-2 block">
						{$t.shop.yourChanceLabel}
						<strong class={getProbabilityColor(item.effectiveProbability)}
							>{item.effectiveProbability.toFixed(1)}%</strong
						>
					</span>
				</p>
				<div class="flex gap-3">
					<button
						onclick={() => (showConfirmation = false)}
						disabled={tryingLuck}
						class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
					>
						{$t.common.cancel}
					</button>
					<button
						onclick={handleTryLuck}
						disabled={tryingLuck}
						class="flex-1 cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed disabled:opacity-50"
					>
						{tryingLuck ? $t.common.trying : $t.common.tryLuck}
					</button>
				</div>
			</div>
		</div>
	{/if}

	{#if alertMessage}
		<div
			class="fixed inset-0 z-70 flex items-center justify-center bg-black/50 p-4"
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

<style>
	@keyframes float {
		0%,
		100% {
			transform: translateY(0);
		}
		50% {
			transform: translateY(-6px);
		}
	}
</style>
