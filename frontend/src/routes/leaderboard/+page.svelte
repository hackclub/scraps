<script lang="ts">
	import { onMount } from 'svelte';
	import { getUser } from '$lib/auth-client';
	import {
		leaderboardStore,
		leaderboardLoading,
		fetchLeaderboard as fetchLeaderboardData,
		probabilityLeadersStore,
		probabilityLeadersLoading,
		fetchProbabilityLeaders
	} from '$lib/stores';
	import { formatHours } from '$lib/utils';
	import { t } from '$lib/i18n';

	let activeTab = $state<'scraps' | 'hours' | 'probability'>('scraps');
	let sortBy = $derived(activeTab === 'probability' ? 'scraps' : activeTab);
	let leaderboard = $derived($leaderboardStore[sortBy as 'scraps' | 'hours']);
	let probabilityLeaders = $derived($probabilityLeadersStore);

	function setActiveTab(value: 'scraps' | 'hours' | 'probability') {
		activeTab = value;
		if (value === 'probability') {
			fetchProbabilityLeaders();
		} else {
			fetchLeaderboardData(value);
		}
	}

	onMount(async () => {
		await getUser();
		fetchLeaderboardData('scraps');
	});
</script>

<svelte:head>
	<title>{$t.leaderboard.leaderboard} - {$t.common.scraps}</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-2 text-4xl font-bold md:text-5xl">{$t.leaderboard.leaderboard}</h1>
	<p class="mb-8 text-lg text-gray-600">{$t.leaderboard.topScrappers}</p>

	<div class="mb-6 flex flex-wrap gap-2">
		<button
			class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {activeTab ===
			'scraps'
				? 'bg-black text-white'
				: 'hover:border-dashed'}"
			onclick={() => setActiveTab('scraps')}
		>
			{$t.leaderboard.scraps}
		</button>
		<button
			class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {activeTab ===
			'hours'
				? 'bg-black text-white'
				: 'hover:border-dashed'}"
			onclick={() => setActiveTab('hours')}
		>
			{$t.leaderboard.hours}
		</button>
		<button
			class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {activeTab ===
			'probability'
				? 'bg-black text-white'
				: 'hover:border-dashed'}"
			onclick={() => setActiveTab('probability')}
		>
			{$t.leaderboard.probabilityLeaders}
		</button>
	</div>

	{#if activeTab === 'probability'}
		<div class="rounded-2xl border-4 border-black p-6">
			{#if $probabilityLeadersLoading && probabilityLeaders.length === 0}
				<div class="text-center text-gray-500">{$t.common.loading}</div>
			{:else if probabilityLeaders.length === 0}
				<div class="text-center text-gray-500">{$t.leaderboard.noProbabilityLeadersYet}</div>
			{:else}
				<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
					{#each probabilityLeaders as leader (leader.itemId)}
						<div class="rounded-2xl border-4 border-black p-4 transition-all hover:border-dashed">
							<div class="mb-3 flex items-center gap-3">
								<img
									src={leader.itemImage}
									alt={leader.itemName}
									class="h-12 w-12 rounded-lg border-2 border-black object-cover"
								/>
								<div>
									<div class="font-bold">{leader.itemName}</div>
									<div class="text-sm text-gray-500">
										{$t.leaderboard.base}: {leader.baseProbability}%
									</div>
								</div>
							</div>
							{#if leader.topUser}
								<a href="/users/{leader.topUser.id}" class="group flex items-center gap-2">
									<img
										src={leader.topUser.avatar}
										alt={leader.topUser.username}
										class="h-8 w-8 rounded-full border-2 border-black object-cover"
									/>
									<span class="font-bold group-hover:underline">{leader.topUser.username}</span>
									<span class="ml-auto font-bold text-green-600"
										>{leader.effectiveProbability}%</span
									>
								</a>
							{:else}
								<div class="text-sm text-gray-500">{$t.leaderboard.noBoostsYet}</div>
							{/if}
						</div>
					{/each}
				</div>
			{/if}
		</div>
	{:else}
		<div class="overflow-hidden rounded-2xl border-4 border-black">
			{#if $leaderboardLoading && leaderboard.length === 0}
				<div class="p-8 text-center text-gray-500">{$t.common.loading}</div>
			{:else}
				<!-- Desktop table -->
				<table class="hidden w-full md:table">
					<thead>
						<tr class="border-b-4 border-black bg-black text-white">
							<th class="px-4 py-4 text-left font-bold">{$t.leaderboard.rank}</th>
							<th class="px-4 py-4 text-left font-bold">{$t.leaderboard.user}</th>
							<th class="px-4 py-4 text-right font-bold">{$t.leaderboard.hours}</th>
							<th class="px-4 py-4 text-right font-bold">{$t.leaderboard.projects}</th>
							<th class="px-4 py-4 text-right font-bold">{$t.leaderboard.scraps}</th>
						</tr>
					</thead>
					<tbody>
						{#each leaderboard as entry (entry.id)}
							<tr
								class="cursor-pointer border-b-2 border-black/20 transition-colors last:border-b-0 hover:bg-gray-50"
								onclick={() => (window.location.href = `/users/${entry.id}`)}
							>
								<td class="px-4 py-4 text-2xl font-bold">
									{#if entry.rank === 1}
										🥇
									{:else if entry.rank === 2}
										🥈
									{:else if entry.rank === 3}
										🥉
									{:else}
										{entry.rank}
									{/if}
								</td>
								<td class="px-4 py-4">
									<a href="/users/{entry.id}" class="flex items-center gap-3">
										<img
											src={entry.avatar}
											alt={entry.username}
											class="h-10 w-10 rounded-full border-2 border-black object-cover"
										/>
										<span class="text-lg font-bold hover:underline">{entry.username}</span>
									</a>
								</td>
								<td class="px-4 py-4 text-right text-lg">{formatHours(entry.hours)}h</td>
								<td class="px-4 py-4 text-right text-lg">{entry.projectCount}</td>
								<td class="px-4 py-4 text-right text-lg">
									<span class="font-bold">{entry.scraps}</span>
									<span class="ml-1 text-sm text-gray-500"
										>({$t.leaderboard.earned}: {entry.scrapsEarned})</span
									>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>

				<!-- Mobile cards -->
				<div class="divide-y-2 divide-black/20 md:hidden">
					{#each leaderboard as entry (entry.id)}
						<a
							href="/users/{entry.id}"
							class="flex cursor-pointer items-center gap-3 p-4 transition-colors hover:bg-gray-50"
						>
							<span class="w-8 shrink-0 text-2xl font-bold">
								{#if entry.rank === 1}
									🥇
								{:else if entry.rank === 2}
									🥈
								{:else if entry.rank === 3}
									🥉
								{:else}
									{entry.rank}
								{/if}
							</span>
							<img
								src={entry.avatar}
								alt={entry.username}
								class="h-10 w-10 shrink-0 rounded-full border-2 border-black object-cover"
							/>
							<div class="min-w-0 flex-1">
								<p class="truncate font-bold">{entry.username}</p>
								<p class="text-sm text-gray-500">
									{formatHours(entry.hours)}h · {entry.projectCount}
									{$t.leaderboard.projects}
								</p>
							</div>
							<div class="shrink-0 text-right">
								<p class="font-bold">{entry.scraps}</p>
								<p class="text-xs text-gray-500">{$t.leaderboard.scraps}</p>
							</div>
						</a>
					{/each}
				</div>
			{/if}
		</div>
	{/if}
</div>
