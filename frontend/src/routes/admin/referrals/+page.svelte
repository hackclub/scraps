<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { ArrowRight } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';

	interface Person {
		id: number;
		username: string | null;
		avatar: string | null;
		verificationStatus?: string;
		verified?: boolean;
	}

	interface Entry {
		id: number;
		code: string;
		createdAt: string;
		referrer: Person;
		referred: Person;
	}

	let loading = $state(true);
	let entries = $state<Entry[]>([]);
	let total = $state(0);
	let verifiedTotal = $state(0);

	onMount(async () => {
		const user = await getUser();
		if (!user || !['reviewer', 'admin', 'creator'].includes(user.role)) {
			goto('/dashboard');
			return;
		}
		const res = await fetch(`${API_URL}/admin/referrals`, { credentials: 'include' });
		if (res.ok) {
			const data = await res.json();
			entries = data.entries;
			total = data.total;
			verifiedTotal = data.verifiedTotal;
		}
		loading = false;
	});

	function fmtDate(s: string) {
		return new Date(s).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
	}
</script>

<svelte:head>
	<title>referrals - scraps admin</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-2 text-4xl font-bold">Referrals</h1>
	<p class="mb-6 text-gray-600">Who invited whom, and whether the invitee verified.</p>

	<div class="mb-8 flex flex-wrap gap-3">
		<div class="rounded-xl border-4 border-black bg-white px-4 py-3">
			<span class="text-2xl font-bold">{total}</span> <span class="text-gray-500">referrals</span>
		</div>
		<div class="rounded-xl border-4 border-black bg-green-100 px-4 py-3">
			<span class="text-2xl font-bold">{verifiedTotal}</span> <span class="text-gray-600">verified</span>
		</div>
	</div>

	{#if loading}
		<p class="text-gray-500">Loading…</p>
	{:else if entries.length === 0}
		<p class="rounded-xl border-2 border-dashed border-gray-300 p-6 text-center text-gray-500">
			No referrals yet.
		</p>
	{:else}
		<ul class="flex flex-col gap-2">
			{#each entries as e (e.id)}
				<li class="flex flex-wrap items-center gap-3 rounded-xl border-2 border-black bg-white px-4 py-3">
					<div class="flex min-w-0 items-center gap-2">
						{#if e.referrer.avatar}
							<img src={e.referrer.avatar} alt="" class="h-8 w-8 rounded-full" />
						{:else}
							<div class="h-8 w-8 rounded-full bg-gray-200"></div>
						{/if}
						<span class="truncate font-bold">{e.referrer.username || `#${e.referrer.id}`}</span>
					</div>

					<ArrowRight size={16} class="shrink-0 text-gray-400" />

					<div class="flex min-w-0 items-center gap-2">
						{#if e.referred.avatar}
							<img src={e.referred.avatar} alt="" class="h-8 w-8 rounded-full" />
						{:else}
							<div class="h-8 w-8 rounded-full bg-gray-200"></div>
						{/if}
						<span class="truncate font-bold">{e.referred.username || `#${e.referred.id}`}</span>
					</div>

					<div class="ml-auto flex shrink-0 items-center gap-2">
						{#if e.referred.verified}
							<span class="rounded-full bg-green-100 px-3 py-1 text-xs font-bold text-green-700">verified</span>
						{:else}
							<span class="rounded-full bg-gray-100 px-3 py-1 text-xs font-bold text-gray-600"
								>{e.referred.verificationStatus || 'unverified'}</span
							>
						{/if}
						<span class="text-xs text-gray-400">{fmtDate(e.createdAt)}</span>
					</div>
				</li>
			{/each}
		</ul>
	{/if}
</div>
