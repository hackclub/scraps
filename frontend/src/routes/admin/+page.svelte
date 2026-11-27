<script lang="ts">
	import { safeUrl } from '$lib/safeUrl';
	import { onMount } from 'svelte';
	import {
		Users,
		FolderKanban,
		Clock,
		Scale,
		Hourglass,
		ShieldAlert,
		Coins,
		XCircle,
		ShoppingCart,
		DollarSign,
		SearchCheck,
		MessageSquare,
		Link,
		Compass
	} from '@lucide/svelte';
	import { getUser, requireLogin } from '$lib/auth-client';
	import { API_URL, serverConfig } from '$lib/config';
	import { t } from '$lib/i18n';
	import { formatHours } from '$lib/utils';
	import CaughtSnooping from '$lib/components/CaughtSnooping.svelte';

	const SCRAPS_PER_HOUR = serverConfig.scrapsPerHour ?? 64;
	const DOLLARS_PER_HOUR = serverConfig.dollarsPerHour ?? 5;
	const SCRAPS_PER_DOLLAR = SCRAPS_PER_HOUR / DOLLARS_PER_HOUR;

	interface ShopStats {
		totalScrapsSpent: number;
		shopPurchases: number;
		shopConsolations: number;
		shopLuckWins: number;
		refineryUpgrades: number;
		costPerHour: number;
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
	}

	let stats = $state<Stats | null>(null);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let isAdmin = $state(false);
	let blocked = $state(false);



	// Unified duplicates state
	interface DuplicateRecord {
		id: string;
		ysws: string;
		playableUrl: string;
		codeUrl: string;
		hours: number | null;
	}
	interface UnifiedDuplicatesResult {
		totalChecked: number;
		nonScrapsMatches: (DuplicateRecord & { matchType: string })[];
	}
	let dupChecking = $state(false);
	let dupResult = $state<UnifiedDuplicatesResult | null>(null);
	let dupError = $state<string | null>(null);

	let exploreEnabled = $state(false);
	let exploreSaving = $state(false);
	let exploreError = $state<string | null>(null);

	async function loadSiteSettings() {
		try {
			const res = await fetch(`${API_URL}/admin/site-settings`, { credentials: 'include' });
			if (!res.ok) return;
			const data = await res.json();
			exploreEnabled = data.explore === true;
		} catch {
			exploreError = 'Failed to load site settings';
		}
	}

	async function toggleExplore() {
		exploreSaving = true;
		exploreError = null;
		try {
			const res = await fetch(`${API_URL}/admin/site-settings/explore`, {
				method: 'PUT',
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ enabled: !exploreEnabled })
			});
			const data = await res.json();
			if (data.error) {
				exploreError = data.error;
			} else {
				exploreEnabled = data.explore === true;
			}
		} catch {
			exploreError = 'Failed to update explore setting';
		} finally {
			exploreSaving = false;
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

	let raffle = $state<{
		total: number;
		users: { id: number; username: string | null; avatar: string | null; tickets: number }[];
		weeks: Record<
			string,
			{
				drawAt: string;
				open: boolean;
				total: number;
				entries: { id: number; username: string | null; tickets: number; updatedAt: string }[];
			}
		>;
	} | null>(null);
	let raffleView = $state<'owned' | '1' | '2' | '3' | '4'>('1');
	let raffleWeek = $derived(raffle && raffleView !== 'owned' ? raffle.weeks[raffleView] : null);

	type Suggestion = {
		id: number;
		name: string;
		image: string | null;
		description: string | null;
		vendorUrl: string;
		createdAt: string;
		userId: number;
		username: string | null;
	};
	let suggestions = $state<Suggestion[] | null>(null);

	async function loadSuggestions() {
		try {
			const res = await fetch(`${API_URL}/admin/item-suggestions`, { credentials: 'include' });
			if (res.ok) suggestions = await res.json();
		} catch {
			suggestions = null;
		}
	}

	async function dismissSuggestion(id: number) {
		const res = await fetch(`${API_URL}/admin/item-suggestions/${id}`, {
			method: 'DELETE',
			credentials: 'include'
		});
		if (res.ok && suggestions) suggestions = suggestions.filter((x) => x.id !== id);
	}

	async function loadRaffleTickets() {
		try {
			const res = await fetch(`${API_URL}/admin/raffle-tickets`, { credentials: 'include' });
			if (res.ok) raffle = await res.json();
		} catch {
			raffle = null;
		}
	}

	onMount(async () => {
		const user = await getUser();
		if (!user) {
			requireLogin();
			return;
		}
		if (user.role !== 'admin' && user.role !== 'reviewer' && user.role !== 'creator') {
			blocked = true;
			return;
		}
		isAdmin = user.role === 'admin' || user.role === 'creator';
		if (isAdmin) {
			loadSiteSettings();
			loadRaffleTickets();
			loadSuggestions();
		}

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
	<title>{blocked ? 'you thought' : $t.admin.adminInfo} - scraps</title>
</svelte:head>

{#if blocked}
	<CaughtSnooping />
{:else}
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

				<div
					class="flex items-center gap-4 rounded-2xl border-4 border-yellow-500 bg-yellow-50 p-6"
				>
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

				<div
					class="flex items-center gap-4 rounded-2xl border-4 border-yellow-500 bg-yellow-50 p-6"
				>
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
					<div
						class="flex h-16 w-16 items-center justify-center rounded-full bg-blue-500 text-white"
					>
						<Hourglass size={32} />
					</div>
					<div>
						<p class="text-sm font-bold text-gray-500">pending review hours</p>
						<p class="text-4xl font-bold text-blue-600">{stats.pendingHours.toLocaleString()}h</p>
					</div>
				</div>

				<div class="flex items-center gap-4 rounded-2xl border-4 border-blue-500 bg-blue-50 p-6">
					<div
						class="flex h-16 w-16 items-center justify-center rounded-full bg-blue-500 text-white"
					>
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

			{#if stats.shopStats}
				<h2 class="mt-10 mb-6 text-2xl font-bold">shop spending</h2>
				<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
					<div
						class="flex items-center gap-4 rounded-2xl border-4 border-green-500 bg-green-50 p-6"
					>
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

					<div
						class="flex items-center gap-4 rounded-2xl border-4 border-green-500 bg-green-50 p-6"
					>
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
						<div
							class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white"
						>
							<Coins size={32} />
						</div>
						<div>
							<p class="text-sm font-bold text-gray-500">shop purchases</p>
							<p class="text-4xl font-bold">{stats.shopStats.shopPurchases.toLocaleString()}</p>
						</div>
					</div>

					<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
						<div
							class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white"
						>
							<Coins size={32} />
						</div>
						<div>
							<p class="text-sm font-bold text-gray-500">consolation scraps</p>
							<p class="text-4xl font-bold">{stats.shopStats.shopConsolations.toLocaleString()}</p>
						</div>
					</div>

					<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
						<div
							class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white"
						>
							<Coins size={32} />
						</div>
						<div>
							<p class="text-sm font-bold text-gray-500">luck wins</p>
							<p class="text-4xl font-bold">{stats.shopStats.shopLuckWins.toLocaleString()}</p>
						</div>
					</div>

					<div class="flex items-center gap-4 rounded-2xl border-4 border-black p-6">
						<div
							class="flex h-16 w-16 items-center justify-center rounded-full bg-black text-white"
						>
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

	{#if isAdmin}
		<div class="mx-auto max-w-4xl px-6 pb-24 md:px-12">
			<h2 class="mb-4 text-2xl font-bold">admin actions</h2>

			<div class="mb-6 rounded-2xl border-4 border-black p-6">
				<div class="mb-3 flex items-center justify-between">
					<h3 class="text-lg font-bold">item suggestions</h3>
					<span class="text-sm text-gray-500"
						>{suggestions ? `${suggestions.length} total` : ''}</span
					>
				</div>
				{#if !suggestions}
					<p class="text-sm text-gray-500">loading...</p>
				{:else if suggestions.length === 0}
					<p class="text-sm text-gray-500">no suggestions yet</p>
				{:else}
					<div class="flex max-h-96 flex-col gap-3 overflow-y-auto">
						{#each suggestions as sg (sg.id)}
							<div class="flex gap-3 rounded-xl border-2 border-black p-3">
								{#if sg.image}
									<img
										src={safeUrl(sg.image)}
										alt=""
										class="h-16 w-16 shrink-0 rounded-lg border-2 border-black object-cover"
									/>
								{/if}
								<div class="min-w-0 flex-1">
									<div class="flex items-start justify-between gap-2">
										<p class="font-bold break-words">{sg.name}</p>
										<button
											onclick={() => dismissSuggestion(sg.id)}
											class="shrink-0 cursor-pointer rounded-full border-2 border-black px-2 py-0.5 text-xs font-bold hover:bg-gray-100"
											>dismiss</button
										>
									</div>
									{#if sg.description}
										<p class="text-sm break-words whitespace-pre-line text-gray-600">
											{sg.description}
										</p>
									{/if}
									<a
										href={safeUrl(sg.vendorUrl)}
										target="_blank"
										rel="noopener noreferrer"
										class="block truncate text-sm underline">{sg.vendorUrl}</a
									>
									<p class="mt-1 text-xs text-gray-400">
										<a href="/admin/users/{sg.userId}" class="hover:underline"
											>{sg.username ?? `user #${sg.userId}`}</a
										>
										· {new Date(sg.createdAt).toLocaleDateString('en-US', {
											month: 'short',
											day: 'numeric'
										})}
									</p>
								</div>
							</div>
						{/each}
					</div>
				{/if}
			</div>

			<div class="mb-6 rounded-2xl border-4 border-black p-6">
				<div class="mb-3 flex items-center justify-between">
					<h3 class="text-lg font-bold">raffle tickets</h3>
					<span class="text-sm text-gray-500"
						>{#if raffleWeek}{raffleWeek.total} placed by {raffleWeek.entries.length} people{:else if raffle}{raffle.total}
							owned{/if}</span
					>
				</div>
				<div class="mb-3 flex flex-wrap gap-2">
					{#each ['1', '2', '3', '4', 'owned'] as const as v (v)}
						<button
							class="cursor-pointer rounded-full border-2 border-black px-3 py-1 text-sm font-bold {raffleView ===
							v
								? 'bg-black text-white'
								: 'hover:bg-gray-100'}"
							onclick={() => (raffleView = v)}>{v === 'owned' ? 'owned' : `week ${v}`}</button
						>
					{/each}
				</div>
				{#if !raffle}
					<p class="text-sm text-gray-500">loading...</p>
				{:else if raffleWeek}
					<p class="mb-2 text-xs text-gray-500">
						draw {new Date(raffleWeek.drawAt).toLocaleString()} · {raffleWeek.open ? 'open' : 'closed'}
					</p>
					{#if raffleWeek.entries.length === 0}
						<p class="text-sm text-gray-500">no tickets placed this week</p>
					{:else}
						<div class="max-h-80 overflow-y-auto">
							<table class="w-full text-sm">
								<thead>
									<tr class="border-b-2 border-black text-left">
										<th class="py-1">user</th>
										<th class="py-1 text-right">tickets</th>
										<th class="py-1 text-right">odds</th>
									</tr>
								</thead>
								<tbody>
									{#each raffleWeek.entries as e (e.id)}
										<tr class="border-b border-gray-200">
											<td class="py-1">
												<a href="/admin/users/{e.id}" class="hover:underline"
													>{e.username ?? `user #${e.id}`}</a
												>
											</td>
											<td class="py-1 text-right font-bold">{e.tickets}</td>
											<td class="py-1 text-right text-gray-500"
												>{((e.tickets / raffleWeek.total) * 100).toFixed(1)}%</td
											>
										</tr>
									{/each}
								</tbody>
							</table>
						</div>
					{/if}
				{:else if raffle.users.length === 0}
					<p class="text-sm text-gray-500">nobody has tickets yet</p>
				{:else}
					<div class="max-h-80 overflow-y-auto">
						<table class="w-full text-sm">
							<thead>
								<tr class="border-b-2 border-black text-left">
									<th class="py-1">user</th>
									<th class="py-1 text-right">tickets</th>
								</tr>
							</thead>
							<tbody>
								{#each raffle.users as u (u.id)}
									<tr class="border-b border-gray-200">
										<td class="py-1">
											<a href="/admin/users/{u.id}" class="hover:underline"
												>{u.username ?? `user #${u.id}`}</a
											>
										</td>
										<td class="py-1 text-right font-bold">{u.tickets}</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
				{/if}
			</div>

			<div class="mb-6 rounded-2xl border-4 border-black p-6">
				<div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
					<div>
						<h3 class="flex items-center gap-2 text-lg font-bold">
							<Compass size={20} />
							explore page
						</h3>
						<p class="text-sm text-gray-500">
							{exploreEnabled
								? 'on: everyone can browse shipped and in-review projects'
								: 'off: only admins can see explore'}
						</p>
					</div>
					<button
						onclick={toggleExplore}
						disabled={exploreSaving}
						role="switch"
						aria-checked={exploreEnabled}
						aria-label="toggle explore page"
						class="relative h-9 w-16 shrink-0 cursor-pointer rounded-full border-4 border-black transition-all disabled:opacity-50 {exploreEnabled
							? 'bg-black'
							: 'bg-white'}"
					>
						<span
							class="absolute top-0.5 h-5 w-5 rounded-full transition-all {exploreEnabled
								? 'left-8 bg-white'
								: 'left-0.5 bg-black'}"
						></span>
					</button>
				</div>
				{#if exploreError}
					<div class="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-600">{exploreError}</div>
				{/if}
			</div>

			<a
				href="/admin/budget"
				class="mb-6 flex items-center justify-between rounded-2xl border-4 border-black p-6 transition-all hover:border-dashed"
			>
				<div>
					<h3 class="flex items-center gap-2 text-lg font-bold">
						<DollarSign size={20} />
						budget
					</h3>
					<p class="text-sm text-gray-500">
						live $ per approved hour, review-queue what-if, spending by route, gachapon payouts
					</p>
				</div>
				<span class="text-xl font-bold">→</span>
			</a>

			<a
				href="/admin/macros"
				class="mb-6 flex items-center justify-between rounded-2xl border-4 border-black p-6 transition-all hover:border-dashed"
			>
				<div>
					<h3 class="flex items-center gap-2 text-lg font-bold">
						<MessageSquare size={20} />
						review macros
					</h3>
					<p class="text-sm text-gray-500">
						short name + full text for common rejection reasons, one click on the review page
					</p>
				</div>
				<span class="text-xl font-bold">→</span>
			</a>

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

			<a
				href="/admin/sources"
				class="mb-6 flex items-center justify-between rounded-2xl border-4 border-black p-6 transition-all hover:border-dashed"
			>
				<div>
					<h3 class="flex items-center gap-2 text-lg font-bold">
						<Link size={20} />
						signup sources
					</h3>
					<p class="text-sm text-gray-500">
						make ?source= links for announcements and see how many signups each one brought in
					</p>
				</div>
				<span class="text-xl font-bold">→</span>
			</a>

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
													>submitted to: {match.ysws}</span
												>
												<span
													class="rounded-full border-2 border-red-600 px-2 py-0.5 text-xs font-bold"
													>{match.hours == null
														? 'hours not listed'
														: `${formatHours(match.hours)}h submitted there`}</span
												>
												<span class="text-xs text-gray-500">matched by: {match.matchType}</span>
											</div>
											{#if match.codeUrl}
												<p class="mt-1 truncate text-sm">
													<span class="font-bold">code:</span>
													<a
														href={safeUrl(match.codeUrl)}
														target="_blank"
														class="text-blue-600 hover:underline">{match.codeUrl}</a
													>
												</p>
											{/if}
											{#if match.playableUrl}
												<p class="truncate text-sm">
													<span class="font-bold">playable:</span>
													<a
														href={safeUrl(match.playableUrl)}
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
								<p class="font-bold text-green-700">no scraps URLs found in other YSWS programs</p>
							</div>
						{/if}
					</div>
				{/if}
			</div>
		</div>
	{/if}
{/if}
