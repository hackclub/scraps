<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { Plus, Trash2, Mail, Hash, ShieldCheck, ShieldOff, Check } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';

	interface Entry {
		id: number;
		identifier: string;
		identifierType: 'email' | 'slack_id';
		note: string | null;
		createdAt: string;
	}

	interface SignedUpUser {
		id: number;
		username: string | null;
		avatar: string | null;
		slackId: string | null;
		email: string | null;
		onList: boolean;
	}

	interface User {
		id: number;
		role: string;
	}

	let user = $state<User | null>(null);
	let entries = $state<Entry[]>([]);
	let gating = $state(false);
	let loading = $state(true);
	let saving = $state(false);

	let newIdentifier = $state('');
	let newNote = $state('');
	let formError = $state<string | null>(null);
	let deleteConfirmId = $state<number | null>(null);

	let userQuery = $state('');
	let userResults = $state<SignedUpUser[]>([]);
	let searchingUsers = $state(false);
	let addingUserId = $state<number | null>(null);
	let searchTimer: ReturnType<typeof setTimeout> | undefined;

	onMount(async () => {
		user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}
		await fetchEntries();
		await searchUsers();
	});

	function onUserQueryInput() {
		clearTimeout(searchTimer);
		searchTimer = setTimeout(searchUsers, 250);
	}

	async function searchUsers() {
		searchingUsers = true;
		try {
			const res = await fetch(
				`${API_URL}/admin/login-allowlist/users?q=${encodeURIComponent(userQuery.trim())}`,
				{ credentials: 'include' }
			);
			if (res.ok) userResults = await res.json();
		} catch (e) {
			console.error('user search failed:', e);
		} finally {
			searchingUsers = false;
		}
	}

	async function addUser(u: SignedUpUser) {
		const identifier = u.email || u.slackId;
		if (!identifier) return;
		addingUserId = u.id;
		try {
			const res = await fetch(`${API_URL}/admin/login-allowlist`, {
				method: 'POST',
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ identifier, note: u.username || undefined })
			});
			if (res.ok) {
				await fetchEntries();
				await searchUsers();
			}
		} catch (e) {
			console.error('add user failed:', e);
		} finally {
			addingUserId = null;
		}
	}

	async function fetchEntries() {
		loading = true;
		try {
			const res = await fetch(`${API_URL}/admin/login-allowlist`, { credentials: 'include' });
			if (res.ok) {
				const data = await res.json();
				entries = data.entries;
				gating = data.gating;
			}
		} catch (e) {
			console.error('Failed to fetch allowlist:', e);
		} finally {
			loading = false;
		}
		if (userResults.length) searchUsers();
	}

	async function addEntry() {
		const identifier = newIdentifier.trim();
		if (!identifier) return;
		saving = true;
		formError = null;
		try {
			const res = await fetch(`${API_URL}/admin/login-allowlist`, {
				method: 'POST',
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ identifier, note: newNote.trim() || undefined })
			});
			if (!res.ok) {
				const err = await res.json().catch(() => ({}));
				formError = err.error || 'Failed to add';
				return;
			}
			newIdentifier = '';
			newNote = '';
			await fetchEntries();
		} catch {
			formError = 'Network error';
		} finally {
			saving = false;
		}
	}

	async function removeEntry(id: number) {
		try {
			const res = await fetch(`${API_URL}/admin/login-allowlist/${id}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			if (res.ok) {
				deleteConfirmId = null;
				await fetchEntries();
			}
		} catch (e) {
			console.error('Failed to delete:', e);
		}
	}
</script>

<svelte:head>
	<title>allowed logins - scraps admin</title>
</svelte:head>

<div class="mx-auto max-w-3xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-2 text-4xl font-bold">Allowed to Log In</h1>
	<p class="mb-6 text-gray-600">
		Add emails or Slack IDs. While this list has at least one entry, only listed people can log in —
		everyone else is turned away at sign-in. Empty the list to reopen sign-up. Existing
		admins/creators can always log in.
	</p>

	<div
		class="mb-8 flex items-center gap-2 rounded-xl border-4 border-black px-4 py-3 font-bold {gating
			? 'bg-green-100'
			: 'bg-yellow-100'}"
	>
		{#if gating}
			<ShieldCheck size={20} /> Login is restricted to the {entries.length} entr{entries.length === 1
				? 'y'
				: 'ies'} below.
		{:else}
			<ShieldOff size={20} /> Login is open — anyone eligible can sign up.
		{/if}
	</div>

	<!-- Add form -->
	<div class="mb-8 rounded-2xl border-4 border-black bg-white p-5">
		<div class="flex flex-col gap-3 sm:flex-row">
			<input
				bind:value={newIdentifier}
				onkeydown={(e) => e.key === 'Enter' && addEntry()}
				placeholder="email@example.com  or  U0XXXXXXX"
				class="flex-1 rounded-full border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
			/>
			<input
				bind:value={newNote}
				onkeydown={(e) => e.key === 'Enter' && addEntry()}
				placeholder="note (optional)"
				class="rounded-full border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none sm:w-40"
			/>
			<button
				onclick={addEntry}
				disabled={saving || !newIdentifier.trim()}
				class="flex items-center justify-center gap-1 rounded-full bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
			>
				<Plus size={16} /> Add
			</button>
		</div>
		{#if formError}
			<p class="mt-2 px-4 text-sm text-red-600">{formError}</p>
		{/if}
		<p class="mt-2 px-4 text-xs text-gray-500">
			Type is detected automatically: contains <code>@</code> → email, otherwise Slack ID.
		</p>
	</div>

	<!-- Pick a signed-up user -->
	<div class="mb-8 rounded-2xl border-4 border-black bg-white p-5">
		<p class="mb-3 font-bold">Or add a signed-up user</p>
		<input
			bind:value={userQuery}
			oninput={onUserQueryInput}
			placeholder="search by name, email, or slack id"
			class="w-full rounded-full border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
		/>
		<ul class="mt-3 flex flex-col gap-2">
			{#each userResults as u (u.id)}
				<li class="flex items-center gap-3 rounded-xl border-2 border-gray-200 px-3 py-2">
					{#if u.avatar}
						<img src={u.avatar} alt="" class="h-8 w-8 shrink-0 rounded-full" />
					{:else}
						<div class="h-8 w-8 shrink-0 rounded-full bg-gray-200"></div>
					{/if}
					<div class="min-w-0 flex-1">
						<p class="truncate text-sm font-bold">{u.username || 'unknown'}</p>
						<p class="truncate text-xs text-gray-500">{u.email || u.slackId}</p>
					</div>
					{#if u.onList}
						<span class="flex shrink-0 items-center gap-1 text-sm font-bold text-green-600">
							<Check size={16} /> on list
						</span>
					{:else}
						<button
							onclick={() => addUser(u)}
							disabled={addingUserId === u.id}
							class="flex shrink-0 items-center gap-1 rounded-full bg-black px-3 py-1 text-sm font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
						>
							<Plus size={14} /> Add
						</button>
					{/if}
				</li>
			{:else}
				<li class="py-3 text-center text-sm text-gray-400">
					{searchingUsers ? 'Searching…' : 'No users found'}
				</li>
			{/each}
		</ul>
		<p class="mt-2 text-xs text-gray-500">Adds their email and Slack ID together.</p>
	</div>

	<!-- List -->
	{#if loading}
		<p class="text-gray-500">Loading…</p>
	{:else if entries.length === 0}
		<p class="rounded-xl border-2 border-dashed border-gray-300 p-6 text-center text-gray-500">
			No entries — login is open.
		</p>
	{:else}
		<ul class="flex flex-col gap-2">
			{#each entries as entry (entry.id)}
				<li
					class="flex items-center gap-3 rounded-xl border-2 border-black bg-white px-4 py-3"
				>
					{#if entry.identifierType === 'email'}
						<Mail size={18} class="shrink-0 text-gray-500" />
					{:else}
						<Hash size={18} class="shrink-0 text-gray-500" />
					{/if}
					<span class="font-mono text-sm">{entry.identifier}</span>
					{#if entry.note}
						<span class="truncate text-sm text-gray-500">— {entry.note}</span>
					{/if}
					<div class="ml-auto shrink-0">
						{#if deleteConfirmId === entry.id}
							<button
								onclick={() => removeEntry(entry.id)}
								class="rounded-full bg-red-600 px-3 py-1 text-sm font-bold text-white">Confirm</button
							>
							<button
								onclick={() => (deleteConfirmId = null)}
								class="rounded-full border-2 border-black px-3 py-1 text-sm font-bold">Cancel</button
							>
						{:else}
							<button
								onclick={() => (deleteConfirmId = entry.id)}
								aria-label="Remove"
								class="rounded-full p-1.5 text-gray-400 transition-colors hover:bg-red-100 hover:text-red-600"
							>
								<Trash2 size={16} />
							</button>
						{/if}
					</div>
				</li>
			{/each}
		</ul>
	{/if}
</div>
