<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { Plus, Trash2, Copy, Check } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';

	interface Source {
		id: number;
		slug: string;
		note: string | null;
		createdAt: string;
		signups: number;
		verified: number;
	}

	interface Untracked {
		slug: string;
		signups: number;
		verified: number;
	}

	let sources = $state<Source[]>([]);
	let untracked = $state<Untracked[]>([]);
	let loading = $state(true);
	let saving = $state(false);

	let newSlug = $state('');
	let newNote = $state('');
	let formError = $state<string | null>(null);
	let deleteConfirmId = $state<number | null>(null);
	let copiedSlug = $state<string | null>(null);

	let origin = $state('');

	onMount(async () => {
		origin = window.location.origin;
		const user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}
		await fetchSources();
	});

	function linkFor(slug: string) {
		return `${origin}/?source=${slug}`;
	}

	async function fetchSources() {
		loading = true;
		try {
			const res = await fetch(`${API_URL}/admin/signup-sources`, { credentials: 'include' });
			if (res.ok) {
				const data = await res.json();
				sources = data.sources;
				untracked = data.untracked;
			}
		} catch (e) {
			console.error('Failed to fetch sources:', e);
		} finally {
			loading = false;
		}
	}

	async function addSource() {
		const slug = newSlug.trim().toLowerCase();
		if (!slug) return;
		saving = true;
		formError = null;
		try {
			const res = await fetch(`${API_URL}/admin/signup-sources`, {
				method: 'POST',
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ slug, note: newNote.trim() || undefined })
			});
			if (!res.ok) {
				const err = await res.json().catch(() => ({}));
				formError = err.error || 'Failed to add';
				return;
			}
			newSlug = '';
			newNote = '';
			await fetchSources();
			copyLink(slug);
		} catch {
			formError = 'Network error';
		} finally {
			saving = false;
		}
	}

	async function removeSource(id: number) {
		try {
			const res = await fetch(`${API_URL}/admin/signup-sources/${id}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			if (res.ok) {
				deleteConfirmId = null;
				await fetchSources();
			}
		} catch (e) {
			console.error('Failed to delete:', e);
		}
	}

	async function copyLink(slug: string) {
		try {
			await navigator.clipboard.writeText(linkFor(slug));
			copiedSlug = slug;
			setTimeout(() => {
				if (copiedSlug === slug) copiedSlug = null;
			}, 1500);
		} catch {
			copiedSlug = null;
		}
	}
</script>

<svelte:head>
	<title>signup sources - scraps admin</title>
</svelte:head>

<div class="mx-auto max-w-3xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-2 text-4xl font-bold">Signup Sources</h1>
	<p class="mb-6 text-gray-600">
		Make a link per place you announce scraps. New accounts that land through a link are tagged
		with its source. Existing users clicking a link are not counted.
	</p>

	<div class="mb-8 rounded-2xl border-4 border-black bg-white p-5">
		<div class="flex flex-col gap-3 sm:flex-row">
			<input
				bind:value={newSlug}
				onkeydown={(e) => e.key === 'Enter' && addSource()}
				placeholder="slack-announcements"
				class="flex-1 rounded-full border-2 border-black px-4 py-2 font-mono focus:border-dashed focus:outline-none"
			/>
			<input
				bind:value={newNote}
				onkeydown={(e) => e.key === 'Enter' && addSource()}
				placeholder="note (optional)"
				class="rounded-full border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none sm:w-48"
			/>
			<button
				onclick={addSource}
				disabled={saving || !newSlug.trim()}
				class="flex items-center justify-center gap-1 rounded-full bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
			>
				<Plus size={16} /> Create
			</button>
		</div>
		{#if formError}
			<p class="mt-2 px-4 text-sm text-red-600">{formError}</p>
		{/if}
		<p class="mt-2 px-4 text-xs text-gray-500">
			Lowercase letters, numbers, <code>-</code> and <code>_</code>. The link is copied when you create
			it.
		</p>
	</div>

	{#if loading}
		<p class="text-gray-500">Loading…</p>
	{:else if sources.length === 0}
		<p class="rounded-xl border-2 border-dashed border-gray-300 p-6 text-center text-gray-500">
			No sources yet.
		</p>
	{:else}
		<ul class="flex flex-col gap-2">
			{#each sources as source (source.id)}
				<li class="rounded-xl border-2 border-black bg-white px-4 py-3">
					<div class="flex items-center gap-3">
						<div class="min-w-0 flex-1">
							<p class="truncate font-mono text-sm font-bold">{source.slug}</p>
							{#if source.note}
								<p class="truncate text-sm text-gray-500">{source.note}</p>
							{/if}
						</div>
						<div class="shrink-0 text-right">
							<p class="text-lg leading-none font-bold">{source.signups}</p>
							<p class="text-xs text-gray-500">{source.verified} verified</p>
						</div>
					</div>
					<div class="mt-2 flex items-center gap-2">
						<button
							onclick={() => copyLink(source.slug)}
							class="flex min-w-0 flex-1 items-center gap-2 rounded-full border-2 border-gray-200 px-3 py-1 text-left text-xs text-gray-600 transition-colors hover:border-black"
						>
							{#if copiedSlug === source.slug}
								<Check size={14} class="shrink-0 text-green-600" />
							{:else}
								<Copy size={14} class="shrink-0" />
							{/if}
							<span class="truncate font-mono">{linkFor(source.slug)}</span>
						</button>
						{#if deleteConfirmId === source.id}
							<button
								onclick={() => removeSource(source.id)}
								class="shrink-0 rounded-full bg-red-600 px-3 py-1 text-sm font-bold text-white"
								>Confirm</button
							>
							<button
								onclick={() => (deleteConfirmId = null)}
								class="shrink-0 rounded-full border-2 border-black px-3 py-1 text-sm font-bold"
								>Cancel</button
							>
						{:else}
							<button
								onclick={() => (deleteConfirmId = source.id)}
								aria-label="Remove"
								class="shrink-0 rounded-full p-1.5 text-gray-400 transition-colors hover:bg-red-100 hover:text-red-600"
							>
								<Trash2 size={16} />
							</button>
						{/if}
					</div>
				</li>
			{/each}
		</ul>
	{/if}

	{#if untracked.length > 0}
		<h2 class="mt-10 mb-2 text-xl font-bold">Not on the list</h2>
		<p class="mb-3 text-sm text-gray-500">
			Signups from <code>?source=</code> values nobody created here.
		</p>
		<ul class="flex flex-col gap-2">
			{#each untracked as u (u.slug)}
				<li
					class="flex items-center gap-3 rounded-xl border-2 border-dashed border-gray-300 px-4 py-2"
				>
					<span class="flex-1 truncate font-mono text-sm">{u.slug}</span>
					<span class="text-sm font-bold">{u.signups}</span>
					<span class="text-xs text-gray-500">{u.verified} verified</span>
				</li>
			{/each}
		</ul>
	{/if}

	<p class="mt-8 text-xs text-gray-500">
		Deleting a source only removes it from this list. Its link keeps working, and its signups
		move to "Not on the list".
	</p>
</div>
