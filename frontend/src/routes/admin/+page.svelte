<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		Users,
		FolderKanban,
		Clock,
		Scale,
		Hourglass,
		ShieldAlert,
		Coins,
		XCircle,
		Download,
		RefreshCw,
		ShoppingCart,
		DollarSign,
		Calculator,
		SearchCheck
	} from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';

	const PHI = (1 + Math.sqrt(5)) / 2;
	const SCRAPS_PER_HOUR = PHI * 10;
	const DOLLARS_PER_HOUR = 4;
	const SCRAPS_PER_DOLLAR = SCRAPS_PER_HOUR / DOLLARS_PER_HOUR;

	interface ShopStats {
		totalScrapsSpent: number;
		shopPurchases: number;
		shopConsolations: number;
		shopLuckWins: number;
		refineryUpgrades: number;
		costPerHour: number;
	}

	interface TierCost {
		tier: number;
		multiplier: number;
		hours: number;
		projects: number;
	}

	interface Stats {
		totalUsers: number;
		totalProjects: number;
		totalHours: number;
		weightedGrants: number;
		pendingHours: number;
		pendingWeightedGrants: number;
		inProgressHours: number;
		inProgressWeightedGrants: number;
		shopStats?: ShopStats;
		tierCostBreakdown?: TierCost[];
	}

	let stats = $state<Stats | null>(null);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let isAdmin = $state(false);

	// Fix balances state
	let fixingBalances = $state(false);
	let fixResult = $state<{
		fixedCount: number;
		fixed: { userId: number; username: string | null; deficit: number }[];
	} | null>(null);
	let fixError = $state<string | null>(null);

	// YSWS sync state
	let yswsSyncing = $state(false);
	let yswsResult = $state<{ synced: number; failed: number; total: number } | null>(null);
	let yswsError = $state<string | null>(null);

	// Shop pricing recalculation state
	let pricingRecalcing = $state(false);
	let pricingResult = $state<{ updatedCount: number } | null>(null);
	let pricingError = $state<string | null>(null);

	// Unified duplicates state
	interface DuplicateRecord {
		id: string;
		ysws: string;
		playableUrl: string;
		codeUrl: string;
	}
	interface UnifiedDuplicatesResult {
		totalChecked: number;
		nonScrapsMatches: (DuplicateRecord & { matchType: string })[];
	}
	let dupChecking = $state(false);
	let dupResult = $state<UnifiedDuplicatesResult | null>(null);
	let dupError = $state<string | null>(null);

	async function fixNegativeBalances() {
		fixingBalances = true;
		fixResult = null;
		fixError = null;
		try {
			const res = await fetch(`${API_URL}/admin/fix-negative-balances`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await res.json();
			if (data.error) {
				fixError = data.error;
			} else {
				fixResult = data;
			}
		} catch (_e) {
			fixError = 'Failed to fix negative balances';
		} finally {
			fixingBalances = false;
		}
	}

	async function recalculateShopPricing() {
		pricingRecalcing = true;
		pricingResult = null;
		pricingError = null;
		try {
			const res = await fetch(`${API_URL}/admin/recalculate-shop-pricing`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await res.json();
			if (data.error) {
				pricingError = data.error;
			} else {
				pricingResult = data;
			}
		} catch {
			pricingError = 'Failed to recalculate shop pricing';
		} finally {
			pricingRecalcing = false;
		}
	}

	async function syncYSWS() {
		yswsSyncing = true;
		yswsResult = null;
		yswsError = null;
		try {
			const res = await fetch(`${API_URL}/admin/sync-ysws`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await res.json();
			if (data.error) {
				yswsError = data.error;
			} else {
				yswsResult = data;
			}
		} catch {
			yswsError = 'Failed to sync projects to YSWS';
		} finally {
			yswsSyncing = false;
		}
	}

	async function checkUnifiedDuplicates() {
		dupChecking = true;
		dupResult = null;
		dupError = null;
		try {
			const res = await fetch(`${API_URL}/admin/unified-duplicates`, {
				credentials: 'include'
			});
			const data = await res.json();
			if (data.error) {
				dupError = data.error;
			} else {
				dupResult = data;
			}
		} catch {
			dupError = 'Failed to check unified airtable';
		} finally {
			dupChecking = false;
		}
	}

	async function downloadExport(endpoint: string, filename: string) {
		try {
			const res = await fetch(`${API_URL}/admin/export/${endpoint}`, {
				credentials: 'include'
			});
			if (!res.ok) return;
			const blob = await res.blob();
			const url = URL.createObjectURL(blob);
			const a = document.createElement('a');
			a.href = url;
			a.download = filename;
			a.click();
			URL.revokeObjectURL(url);
		} catch (e) {
			console.error('Export failed:', e);
		}
	}

	onMount(async () => {
		const user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'reviewer' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}
		isAdmin = user.role === 'admin' || user.role === 'creator';

		try {
			const response = await fetch(`${API_URL}/admin/stats`, {
				credentials: 'include'
			});
			if (!response.ok) throw new Error('Failed to fetch stats');
			stats = await response.json();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load stats';
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head>
	<title>{$t.admin.adminInfo} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-8 text-4xl font-bold md:text-5xl">{$t.admin.adminInfo}</h1>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.admin.loadingStats}</div>
	{:else if error}
		<div class="py-12 text-center text-red-600">{$t.common.error}: {error}</div>
	{:else if stats}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
				<div class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
					<Users size={32} />
				</div>
				<div>
					<p class="text-sm font-bold text-gray-500">total users</p>
					<p class="text-4xl font-bold">{stats.totalUsers.toLocaleString()}</p>
				</div>
			</div>

			<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
				<div class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
					<FolderKanban size={32} />
				</div>
				<div>
					<p class="text-sm font-bold text-gray-500">total projects</p>
					<p class="text-4xl font-bold">{stats.totalProjects.toLocaleString()}</p>
				</div>
			</div>

			<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
				<div class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
					<Clock size={32} />
				</div>
				<div>
					<p class="text-sm font-bold text-gray-500">total shipped hours</p>
					<p class="text-4xl font-bold">{stats.totalHours.toLocaleString()}h</p>
				</div>
			</div>

			<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
				<div class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
					<Scale size={32} />
				</div>
				<div>
					<p class="text-sm font-bold text-gray-500">weighted grants</p>
					<p class="text-4xl font-bold">{stats.weightedGrants.toLocaleString()}</p>
					<p class="text-xs text-gray-400">total hours ÷ 10</p>
				</div>
			</div>

			<div class="flex items-center gap-4 rounded-2xl border-4 border-yellow-500 bg-yellow-50 p-6">
				<div
					class="flex h-16 w-16 items-center justify-center rounded-full bg-yellow-500 text-white"
				>
					<Hourglass size={32} />
				</div>
				<div>
					<p class="text-sm font-bold text-gray-500">in progress hours</p>
					<p class="text-4xl font-bold text-yellow-600">
						{stats.inProgressHours.toLocaleString()}h
					</p>
				</div>
			</div>

			<div class="flex items-center gap-4 rounded-2xl border-4 border-yellow-500 bg-yellow-50 p-6">
				<div
					class="flex h-16 w-16 items-center justify-center rounded-full bg-yellow-500 text-white"
				>
					<Scale size={32} />
				</div>
				<div>
					<p class="text-sm font-bold text-gray-500">in progress weighted grants</p>
					<p class="text-4xl font-bold text-yellow-600">
						{stats.inProgressWeightedGrants.toLocaleString()}
					</p>
					<p class="text-xs text-gray-400">in progress hours ÷ 10</p>
				</div>
			</div>

			<div class="flex items-center gap-4 rounded-2xl border-4 border-blue-500 bg-blue-50 p-6">
				<div class="flex h-16 w-16 items-center justify-center rounded-full bg-blue-500 text-white">
					<Hourglass size={32} />
				</div>
				<div>
					<p class="text-sm font-bold text-gray-500">pending review hours</p>
					<p class="text-4xl font-bold text-blue-600">{stats.pendingHours.toLocaleString()}h</p>
				</div>
			</div>

			<div class="flex items-center gap-4 rounded-2xl border-4 border-blue-500 bg-blue-50 p-6">
				<div class="flex h-16 w-16 items-center justify-center rounded-full bg-blue-500 text-white">
					<Scale size={32} />
				</div>
				<div>
					<p class="text-sm font-bold text-gray-500">pending weighted grants</p>
					<p class="text-4xl font-bold text-blue-600">
						{stats.pendingWeightedGrants.toLocaleString()}
					</p>
					<p class="text-xs text-gray-400">pending hours ÷ 10</p>
				</div>
			</div>
		</div>

		{#if stats.tierCostBreakdown && stats.tierCostBreakdown.length > 0}
			<h2 class="mt-10 mb-6 text-2xl font-bold">projects by tier</h2>
			<div class="rounded-2xl border-4 border-black p-6">
				<table class="w-full text-left">
					<thead>
						<tr class="border-b-2 border-black">
							<th class="pb-2 font-bold">tier</th>
							<th class="pb-2 font-bold">multiplier</th>
							<th class="pb-2 font-bold">hours</th>
							<th class="pb-2 text-right font-bold">projects</th>
						</tr>
					</thead>
					<tbody>
						{#each stats.tierCostBreakdown as tier}
							<tr class="border-b border-gray-200">
								<td class="py-2 font-bold">T{tier.tier}</td>
								<td class="py-2">{tier.multiplier}x</td>
								<td class="py-2">{tier.hours.toLocaleString()}h</td>
								<td class="py-2 text-right font-bold">{tier.projects.toLocaleString()}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}

		{#if stats.shopStats}
			<h2 class="mt-10 mb-6 text-2xl font-bold">shop spending</h2>
			<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
				<div class="flex items-center gap-4 rounded-2xl border-4 border-green-500 bg-green-50 p-6">
					<div
						class="flex h-16 w-16 items-center justify-center rounded-full bg-green-600 text-white"
					>
						<DollarSign size={32} />
					</div>
					<div>
						<p class="text-sm font-bold text-gray-500">shop cost per hour</p>
						<p class="text-4xl font-bold text-green-700">
							${(stats.shopStats.costPerHour / SCRAPS_PER_DOLLAR).toFixed(2)}
						</p>
						<p class="text-xs text-gray-400">scraps spent ÷ shipped hours (in USD)</p>
					</div>
				</div>

				<div class="flex items-center gap-4 rounded-2xl border-4 border-green-500 bg-green-50 p-6">
					<div
						class="flex h-16 w-16 items-center justify-center rounded-full bg-green-600 text-white"
					>
						<ShoppingCart size={32} />
					</div>
					<div>
						<p class="text-sm font-bold text-gray-500">total scraps spent</p>
						<p class="text-4xl font-bold text-green-700">
							{stats.shopStats.totalScrapsSpent.toLocaleString()}
						</p>
						<p class="text-xs text-gray-400">shop + refinery</p>
					</div>
				</div>

				<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
					<div class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
						<Coins size={32} />
					</div>
					<div>
						<p class="text-sm font-bold text-gray-500">shop purchases</p>
						<p class="text-4xl font-bold">{stats.shopStats.shopPurchases.toLocaleString()}</p>
					</div>
				</div>

				<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
					<div class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
						<Coins size={32} />
					</div>
					<div>
						<p class="text-sm font-bold text-gray-500">consolation scraps</p>
						<p class="text-4xl font-bold">{stats.shopStats.shopConsolations.toLocaleString()}</p>
					</div>
				</div>

				<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
					<div class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
						<Coins size={32} />
					</div>
					<div>
						<p class="text-sm font-bold text-gray-500">luck wins</p>
						<p class="text-4xl font-bold">{stats.shopStats.shopLuckWins.toLocaleString()}</p>
					</div>
				</div>

				<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
					<div class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
						<Coins size={32} />
					</div>
					<div>
						<p class="text-sm font-bold text-gray-500">refinery upgrades</p>
						<p class="text-4xl font-bold">{stats.shopStats.refineryUpgrades.toLocaleString()}</p>
					</div>
				</div>
			</div>
		{/if}

	{/if}
</div>

<div class="mx-auto max-w-4xl px-6 pb-12 md:px-12">
	<h2 class="mb-4 text-2xl font-bold">exports</h2>
	<div class="rounded-2xl border-4 border-black p-6">
		<div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
			<div>
				<h3 class="flex items-center gap-2 text-lg font-bold">
					<Download size={20} />
					YSWS review export
				</h3>
				<p class="text-sm text-gray-500">download projects under review for YSWS fraud checking</p>
			</div>
			<div class="flex gap-3">
				<button
					onclick={() => downloadExport('review-csv', 'scraps-review-projects.csv')}
					class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
				>
					CSV
				</button>
				<button
					onclick={() => downloadExport('review-json', 'scraps-review.json')}
					class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
				>
					JSON
				</button>
			</div>
		</div>
	</div>
</div>

{#if isAdmin}
	<div class="mx-auto max-w-4xl px-6 pb-24 md:px-12">
		<h2 class="mb-4 text-2xl font-bold">admin actions</h2>

		<!-- Allowed to Log In -->
		<a
			href="/admin/allowlist"
			class="mb-6 flex items-center justify-between rounded-2xl border-4 border-black p-6 transition-all hover:border-dashed"
		>
			<div>
				<h3 class="flex items-center gap-2 text-lg font-bold">
					<ShieldAlert size={20} />
					allowed to log in
				</h3>
				<p class="text-sm text-gray-500">
					restrict sign-in to specific emails / slack ids (leave empty to allow everyone)
				</p>
			</div>
			<span class="text-xl font-bold">→</span>
		</a>

		<!-- Referrals -->
		<div class="mb-6 rounded-2xl border-4 border-black p-6">
			<div class="flex items-center justify-between">
				<div>
					<h3 class="flex items-center gap-2 text-lg font-bold">
						<Users size={20} />
						referrals
					</h3>
					<p class="text-sm text-gray-500">who invited whom, and whether the invitee verified</p>
				</div>
			</div>
			<div class="mt-4 flex flex-wrap gap-3">
				<a
					href="/admin/referrals"
					class="rounded-full bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800"
				>
					admin view →
				</a>
				<a
					href="/referrals"
					class="rounded-full border-2 border-black px-5 py-2 font-bold transition-all hover:border-dashed"
				>
					public page →
				</a>
			</div>
		</div>

		<!-- Sync to YSWS -->
		<div class="mb-6 rounded-2xl border-4 border-black p-6">
			<div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
				<div>
					<h3 class="flex items-center gap-2 text-lg font-bold">
						<RefreshCw size={20} />
						sync projects to YSWS
					</h3>
					<p class="text-sm text-gray-500">
						submit all submitted/pending/shipped projects to the YSWS fraud API
					</p>
				</div>
				<button
					onclick={syncYSWS}
					disabled={yswsSyncing}
					class="cursor-pointer rounded-full bg-black px-6 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
				>
					{yswsSyncing ? 'syncing...' : 'sync now'}
				</button>
			</div>

			{#if yswsError}
				<div class="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-600">{yswsError}</div>
			{/if}

			{#if yswsResult}
				<div class="mt-4 rounded-lg bg-green-50 p-4">
					<p class="font-bold text-green-700">
						synced {yswsResult.synced} of {yswsResult.total} project{yswsResult.total !== 1
							? 's'
							: ''}
						{#if yswsResult.failed > 0}
							<span class="text-red-600">({yswsResult.failed} failed)</span>
						{/if}
					</p>
				</div>
			{/if}
		</div>

		<!-- Recalculate Shop Pricing -->
		<div class="mb-6 rounded-2xl border-4 border-black p-6">
			<div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
				<div>
					<h3 class="flex items-center gap-2 text-lg font-bold">
						<Calculator size={20} />
						recalculate shop pricing
					</h3>
					<p class="text-sm text-gray-500">
						recalculates probability, upgrade cost, multiplier & boost for all shop items based on
						current price/stock. runs automatically on server startup.
					</p>
				</div>
				<button
					onclick={recalculateShopPricing}
					disabled={pricingRecalcing}
					class="cursor-pointer rounded-full bg-black px-6 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
				>
					{pricingRecalcing ? 'recalculating...' : 'recalculate'}
				</button>
			</div>

			{#if pricingError}
				<div class="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-600">{pricingError}</div>
			{/if}

			{#if pricingResult}
				<div class="mt-4 rounded-lg bg-green-50 p-4">
					<p class="font-bold text-green-700">
						updated pricing for {pricingResult.updatedCount} shop item{pricingResult.updatedCount !==
						1
							? 's'
							: ''}
					</p>
				</div>
			{/if}
		</div>

		<!-- Check Unified Airtable Duplicates -->
		<div class="mb-6 rounded-2xl border-4 border-black p-6">
			<div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
				<div>
					<h3 class="flex items-center gap-2 text-lg font-bold">
						<SearchCheck size={20} />
						check unified airtable duplicates
					</h3>
					<p class="text-sm text-gray-500">
						find projects submitted to other YSWS programs with the same code or playable URL
					</p>
				</div>
				<button
					onclick={checkUnifiedDuplicates}
					disabled={dupChecking}
					class="cursor-pointer rounded-full bg-black px-6 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
				>
					{dupChecking ? 'checking...' : 'check now'}
				</button>
			</div>

			{#if dupError}
				<div class="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-600">{dupError}</div>
			{/if}

			{#if dupResult}
				<div class="mt-4 space-y-4">
					<p class="text-sm text-gray-500">
						checked {dupResult.totalChecked.toLocaleString()} scraps URLs against unified airtable
					</p>

					{#if dupResult.nonScrapsMatches.length > 0}
						<div>
							<h4 class="mb-2 text-sm font-bold text-red-600 uppercase">
								scraps URLs found in other YSWS programs ({dupResult.nonScrapsMatches.length})
							</h4>
							<div class="max-h-96 space-y-2 overflow-y-auto">
								{#each dupResult.nonScrapsMatches as match}
									<div class="rounded-xl border-2 border-red-200 bg-red-50 p-3">
										<div class="flex flex-wrap items-center gap-2">
											<span
												class="rounded-full bg-red-600 px-2 py-0.5 text-xs font-bold text-white"
												>{match.ysws}</span
											>
											<span class="text-xs text-gray-500">matched by: {match.matchType}</span>
										</div>
										{#if match.codeUrl}
											<p class="mt-1 truncate text-sm">
												<span class="font-bold">code:</span>
												<a
													href={match.codeUrl}
													target="_blank"
													class="text-blue-600 hover:underline">{match.codeUrl}</a
												>
											</p>
										{/if}
										{#if match.playableUrl}
											<p class="truncate text-sm">
												<span class="font-bold">playable:</span>
												<a
													href={match.playableUrl}
													target="_blank"
													class="text-blue-600 hover:underline">{match.playableUrl}</a
												>
											</p>
										{/if}
									</div>
								{/each}
							</div>
						</div>
					{:else}
						<div class="rounded-lg bg-green-50 p-4">
							<p class="font-bold text-green-700">
								no scraps URLs found in other YSWS programs
							</p>
						</div>
					{/if}
				</div>
			{/if}
		</div>

		<!-- Fix Negative Balances -->
		<div class="rounded-2xl border-4 border-black p-6">
			<div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
				<div>
					<h3 class="flex items-center gap-2 text-lg font-bold">
						<ShieldAlert size={20} />
						fix negative balances
					</h3>
					<p class="text-sm text-gray-500">
						gives a bonus to all users with negative scraps balance to bring them to 0
					</p>
				</div>
				<button
					onclick={fixNegativeBalances}
					disabled={fixingBalances}
					class="cursor-pointer rounded-full bg-red-600 px-6 py-2 font-bold text-white transition-all hover:bg-red-700 disabled:opacity-50"
				>
					{fixingBalances ? 'running...' : 'run fix'}
				</button>
			</div>

			{#if fixError}
				<div class="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-600">{fixError}</div>
			{/if}

			{#if fixResult}
				<div class="mt-4 rounded-lg bg-green-50 p-4">
					<p class="font-bold text-green-700">
						fixed {fixResult.fixedCount} user{fixResult.fixedCount !== 1 ? 's' : ''}
					</p>
					{#if fixResult.fixed.length > 0}
						<ul class="mt-2 space-y-1 text-sm text-green-800">
							{#each fixResult.fixed as u}
								<li>
									<span class="font-medium">{u.username ?? `User #${u.userId}`}</span>
									— awarded {u.deficit} scraps
								</li>
							{/each}
						</ul>
					{:else}
						<p class="mt-1 text-sm text-green-600">no users had negative balances</p>
					{/if}
				</div>
			{/if}
		</div>
	</div>
{/if}
