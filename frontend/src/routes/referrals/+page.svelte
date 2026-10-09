<script lang="ts">
	import { onMount } from 'svelte';
	import {
		Copy,
		Check,
		Trophy,
		Users,
		Gift,
		PackagePlus,
		CalendarPlus,
		Crown
	} from '@lucide/svelte';
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
	}

	interface Milestone {
		key: string;
		count: number;
		label: string;
		kind: 'slot' | 'daily' | 'item';
		image: string | null;
		icon?: string | null;
		reached: boolean;
		claimed: boolean;
	}

	interface MyReferrals {
		code: string;
		link: string;
		total: number;
		verifiedCount: number;
		referrals: Invitee[];
		milestones: Milestone[];
	}

	let loggedIn = $state(false);
	let loading = $state(true);
	let leaderboard = $state<LeaderRow[]>([]);
	let mine = $state<MyReferrals | null>(null);
	let copied = $state(false);
	let claiming = $state<string | null>(null);
	let claimMessage = $state<{ ok: boolean; text: string; link?: string } | null>(null);

	let maxCount = $derived(
		mine?.milestones?.length ? Math.max(...mine.milestones.map((m) => m.count)) : 20
	);
	let progressPct = $derived(
		mine ? Math.min(100, (mine.verifiedCount / Math.max(maxCount, 1)) * 100) : 0
	);
	let nextMilestone = $derived(mine?.milestones?.find((m) => !m.reached) ?? null);

	async function claim(m: Milestone) {
		claiming = m.key;
		claimMessage = null;
		try {
			const res = await fetch(`${API_URL}/referrals/claim/${m.key}`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await res.json();
			if (!res.ok || data.error) {
				claimMessage = { ok: false, text: data.error || 'Could not claim reward' };
				return;
			}
			if (mine) {
				mine.milestones = mine.milestones.map((x) =>
					x.key === m.key ? { ...x, claimed: true } : x
				);
			}
			claimMessage = {
				ok: true,
				text:
					m.kind === 'slot'
						? 'Claimed! You now have an extra shop slot.'
						: m.kind === 'daily'
							? 'Claimed! You now get 2 extra picks in the shop every day.'
							: `Claimed ${m.label}! Add your shipping address so we can send it.`,
				link: m.kind === 'item' ? '/orders' : undefined
			};
		} catch {
			claimMessage = { ok: false, text: 'Could not claim reward' };
		} finally {
			claiming = null;
		}
	}

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

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-2 text-4xl font-bold md:text-5xl">invite friends</h1>
	<p class="mb-8 text-lg text-gray-600">
		Check the link below and get other people to join with it! Once they sign up and get verified,
		they count toward your rewards :)
	</p>

	<div class="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
		<div class="min-w-0">
			{#if loggedIn && mine}
				{#if mine.milestones?.length}
					<div class="mb-8 rounded-2xl border-4 border-black bg-white p-5">
						<p class="mb-1 flex items-center gap-2 font-bold"><Gift size={18} /> rewards</p>
						<p class="mb-6 text-sm text-gray-500">
							{#if nextMilestone}
								{nextMilestone.count - mine.verifiedCount} more verified
								{nextMilestone.count - mine.verifiedCount === 1 ? 'referral' : 'referrals'} until
								{nextMilestone.label}
							{:else}
								you hit every milestone!
							{/if}
						</p>

						<div class="relative mx-6 mb-2 h-4 rounded-full border-2 border-black bg-gray-100">
							<div
								class="h-full rounded-full bg-black transition-all duration-500"
								style="width: {progressPct}%"
							></div>
							{#each mine.milestones as m (m.key)}
								<div
									class="absolute top-1/2 h-6 w-6 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-black {m.reached
										? 'bg-black'
										: 'bg-white'}"
									style="left: {(m.count / maxCount) * 100}%"
								></div>
							{/each}
						</div>
						<div class="relative mx-6 mb-6 h-5 text-xs font-bold">
							<span class="absolute left-0 -translate-x-1/2">0</span>
							{#each mine.milestones as m (m.key)}
								<span class="absolute -translate-x-1/2" style="left: {(m.count / maxCount) * 100}%"
									>{m.count}</span
								>
							{/each}
						</div>

						<ul class="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
							{#each mine.milestones as m (m.key)}
								<li
									class="flex flex-col items-center gap-2 rounded-xl border-2 p-3 text-center {m.reached
										? 'border-black'
										: 'border-dashed border-gray-300'}"
								>
									<div class="flex h-16 w-16 items-center justify-center">
										{#if m.icon === 'question'}
											<span
												class="text-5xl leading-none font-bold {m.reached ? '' : 'text-gray-300'}"
												>?</span
											>
										{:else if m.image}
											<img
												src={m.image}
												alt={m.label}
												class="max-h-16 max-w-16 object-contain {m.reached
													? ''
													: 'opacity-40 grayscale'}"
											/>
										{:else if m.kind === 'daily'}
											<CalendarPlus size={36} class={m.reached ? '' : 'text-gray-300'} />
										{:else}
											<PackagePlus size={36} class={m.reached ? '' : 'text-gray-300'} />
										{/if}
									</div>
									<p class="text-xs font-bold text-gray-500">{m.count} verified</p>
									<p class="font-bold">{m.label}</p>
									{#if m.claimed}
										<span
											class="rounded-full bg-green-100 px-3 py-1 text-xs font-bold text-green-700"
											>claimed</span
										>
									{:else if m.reached}
										<button
											onclick={() => claim(m)}
											disabled={claiming !== null}
											class="cursor-pointer rounded-full bg-black px-4 py-1 text-sm font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
										>
											{claiming === m.key ? 'claiming...' : 'claim'}
										</button>
									{:else}
										<span class="rounded-full bg-gray-100 px-3 py-1 text-xs font-bold text-gray-500"
											>locked</span
										>
									{/if}
								</li>
							{/each}
						</ul>

						{#if claimMessage}
							<div
								class="mt-4 rounded-lg p-3 text-sm {claimMessage.ok
									? 'bg-green-50 text-green-700'
									: 'bg-red-50 text-red-600'}"
							>
								{claimMessage.text}
								{#if claimMessage.link}
									<a href={claimMessage.link} class="font-bold underline">go to orders</a>
								{/if}
							</div>
						{/if}
					</div>
				{/if}
				<div class="mb-8 rounded-2xl border-4 border-black bg-white p-5">
					<p class="mb-3 font-bold">your invite link</p>
					<div class="flex flex-col gap-3 sm:flex-row">
						<input
							readonly
							value={mine.link}
							class="min-w-0 flex-1 rounded-full border-2 border-black px-4 py-2 font-mono text-sm"
						/>
						<button
							onclick={copyLink}
							class="flex cursor-pointer items-center justify-center gap-1 rounded-full bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800"
						>
							{#if copied}<Check size={16} /> copied{:else}<Copy size={16} /> copy{/if}
						</button>
					</div>
					<div class="mt-4 flex gap-6 text-sm">
						<span><span class="text-xl font-bold">{mine.verifiedCount}</span> verified</span>
						<span class="text-gray-500"
							><span class="text-xl font-bold">{mine.total}</span> total invited</span
						>
					</div>
				</div>

				{#if mine.referrals.length}
					<div class="mb-10">
						<p class="mb-3 flex items-center gap-2 font-bold"><Users size={18} /> your invitees</p>
						<ul class="flex gap-3 overflow-x-auto pb-2">
							{#each mine.referrals as inv (inv.createdAt)}
								<li
									class="flex w-28 shrink-0 flex-col items-center gap-2 rounded-xl border-2 border-black bg-white p-3 text-center"
								>
									{#if inv.avatar}
										<img src={inv.avatar} alt="" class="h-10 w-10 rounded-full" />
									{:else}
										<div class="h-10 w-10 rounded-full bg-gray-200"></div>
									{/if}
									<span class="w-full truncate text-sm font-bold">{inv.username || 'someone'}</span>
									{#if inv.verified}
										<span
											class="rounded-full bg-green-100 px-2 py-0.5 text-xs font-bold text-green-700"
											>verified</span
										>
									{:else}
										<span
											class="rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-bold text-yellow-700"
											>pending</span
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
						class="cursor-pointer rounded-full bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800"
					>
						log in
					</button>
				</div>
			{/if}
		</div>

		<div class="min-w-0">
			<h2 class="mb-3 flex items-center gap-2 text-2xl font-bold">
				<Trophy size={22} /> top referrers
			</h2>
			<div
				class="mb-4 flex items-center gap-4 rounded-2xl border-4 border-yellow-400 bg-yellow-50 p-4"
			>
				<img
					src="https://scrapsv2.hackclub-assets.com/uploads/scrap-1790303068000.png"
					alt="BLÅHAJ"
					class="h-16 w-16 shrink-0 object-contain"
				/>
				<div>
					<p class="flex items-center gap-1 font-bold">
						<Crown size={18} class="text-yellow-500" /> grand prize
					</p>
					<p class="text-sm text-gray-700">
						The person with the most verified referrals of all time gets a <strong>BLÅHAJ</strong>!
					</p>
				</div>
			</div>
			{#if loading}
				<p class="text-gray-500">loading…</p>
			{:else if leaderboard.length === 0}
				<p class="rounded-xl border-2 border-dashed border-gray-300 p-6 text-center text-gray-500">
					no referrals yet! Go become the first!
				</p>
			{:else}
				<ul class="flex flex-col gap-2">
					{#each leaderboard as row (row.rank)}
						<li
							class="flex items-center gap-3 rounded-xl px-4 py-3 {row.rank === 1
								? 'border-4 border-yellow-400 bg-yellow-50'
								: 'border-2 border-black bg-white'}"
						>
							{#if row.rank === 1}
								<span class="flex w-6 justify-center" title="#1 of all time">
									<Crown size={22} class="fill-yellow-400 text-yellow-600" />
								</span>
							{:else}
								<span class="w-6 text-center font-mono font-bold">{row.rank}</span>
							{/if}
							{#if row.avatar}
								<img src={row.avatar} alt="" class="h-9 w-9 rounded-full" />
							{:else}
								<div class="h-9 w-9 rounded-full bg-gray-200"></div>
							{/if}
							<span class="flex-1 truncate font-bold">{row.username || 'someone'}</span>
							<span class="font-bold">{row.verifiedCount}</span>
							<span class="text-sm text-gray-500"
								>verified{row.total > row.verifiedCount ? ` (${row.total} total)` : ''}</span
							>
						</li>
					{/each}
				</ul>
			{/if}
		</div>
	</div>
</div>
