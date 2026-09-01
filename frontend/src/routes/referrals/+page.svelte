<script lang="ts">
	import { onMount } from 'svelte';
	import { Copy, Check, Trophy, Users } from '@lucide/svelte';
	import { getUser, login } from '$lib/auth-client';
	import { API_URL } from '$lib/config';

	interface LeaderRow {
		rank: number;
		username: string | null;
		avatar: string | null;
		verifiedCount: number;
		total: number;
	}

	interface Invitee {
		username: string | null;
		avatar: string | null;
		verified: boolean;
		createdAt: string;
		rewarded: boolean;
	}

	interface MyReferrals {
		code: string;
		link: string;
		rewardAmount: number;
		total: number;
		verifiedCount: number;
		referrals: Invitee[];
	}

	let loggedIn = $state(false);
	let loading = $state(true);
	let leaderboard = $state<LeaderRow[]>([]);
	let mine = $state<MyReferrals | null>(null);
	let copied = $state(false);

	onMount(async () => {
		const user = await getUser();
		loggedIn = !!user;

		const [lb, me] = await Promise.all([
			fetch(`${API_URL}/referrals/leaderboard`).then((r) => (r.ok ? r.json() : [])),
			loggedIn
				? fetch(`${API_URL}/referrals/me`, { credentials: 'include' }).then((r) =>
						r.ok ? r.json() : null
					)
				: Promise.resolve(null)
		]);
		leaderboard = lb;
		mine = me;
		loading = false;
	});

	async function copyLink() {
		if (!mine) return;
		await navigator.clipboard.writeText(mine.link);
		copied = true;
		setTimeout(() => (copied = false), 1500);
	}
</script>

<svelte:head>
	<title>referrals - scraps</title>
</svelte:head>

<div class="mx-auto max-w-3xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-2 text-4xl font-bold md:text-5xl">invite friends</h1>
	<p class="mb-8 text-lg text-gray-600">
		share your link. when someone you invite verifies with hack club auth, it counts.
	</p>

	{#if loggedIn && mine}
		<div class="mb-8 rounded-2xl border-4 border-black bg-white p-5">
			<p class="mb-3 font-bold">your invite link</p>
			<div class="flex flex-col gap-3 sm:flex-row">
				<input
					readonly
					value={mine.link}
					class="flex-1 rounded-full border-2 border-black px-4 py-2 font-mono text-sm"
				/>
				<button
					onclick={copyLink}
					class="flex items-center justify-center gap-1 rounded-full bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800"
				>
					{#if copied}<Check size={16} /> copied{:else}<Copy size={16} /> copy{/if}
				</button>
			</div>
			<div class="mt-4 flex gap-6 text-sm">
				<span><span class="text-xl font-bold">{mine.verifiedCount}</span> verified</span>
				<span class="text-gray-500"
					><span class="text-xl font-bold">{mine.total}</span> total invited</span
				>
				{#if mine.rewardAmount > 0}
					<span class="text-gray-500">{mine.rewardAmount} scraps per verified invite</span>
				{/if}
			</div>
		</div>

		{#if mine.referrals.length}
			<div class="mb-10">
				<p class="mb-3 flex items-center gap-2 font-bold"><Users size={18} /> your invitees</p>
				<ul class="flex flex-col gap-2">
					{#each mine.referrals as inv (inv.createdAt)}
						<li class="flex items-center gap-3 rounded-xl border-2 border-black bg-white px-4 py-2">
							{#if inv.avatar}
								<img src={inv.avatar} alt="" class="h-8 w-8 rounded-full" />
							{:else}
								<div class="h-8 w-8 rounded-full bg-gray-200"></div>
							{/if}
							<span class="flex-1 truncate font-bold">{inv.username || 'someone'}</span>
							{#if inv.verified}
								<span class="rounded-full bg-green-100 px-3 py-1 text-xs font-bold text-green-700"
									>verified</span
								>
							{:else}
								<span class="rounded-full bg-yellow-100 px-3 py-1 text-xs font-bold text-yellow-700"
									>not verified yet</span
								>
							{/if}
						</li>
					{/each}
				</ul>
			</div>
		{/if}
	{:else if !loading && !loggedIn}
		<div class="mb-10 rounded-2xl border-4 border-black bg-white p-5">
			<p class="mb-3 font-bold">get your invite link</p>
			<button
				onclick={() => login()}
				class="rounded-full bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800"
			>
				log in
			</button>
		</div>
	{/if}

	<h2 class="mb-3 flex items-center gap-2 text-2xl font-bold"><Trophy size={22} /> top referrers</h2>
	{#if loading}
		<p class="text-gray-500">loading…</p>
	{:else if leaderboard.length === 0}
		<p class="rounded-xl border-2 border-dashed border-gray-300 p-6 text-center text-gray-500">
			no verified referrals yet — be the first.
		</p>
	{:else}
		<ul class="flex flex-col gap-2">
			{#each leaderboard as row (row.rank)}
				<li class="flex items-center gap-3 rounded-xl border-2 border-black bg-white px-4 py-3">
					<span class="w-6 text-center font-mono font-bold">{row.rank}</span>
					{#if row.avatar}
						<img src={row.avatar} alt="" class="h-9 w-9 rounded-full" />
					{:else}
						<div class="h-9 w-9 rounded-full bg-gray-200"></div>
					{/if}
					<span class="flex-1 truncate font-bold">{row.username || 'someone'}</span>
					<span class="font-bold">{row.verifiedCount}</span>
					<span class="text-sm text-gray-500">verified{row.total > row.verifiedCount ? ` (${row.total} total)` : ''}</span>
				</li>
			{/each}
		</ul>
	{/if}
</div>
