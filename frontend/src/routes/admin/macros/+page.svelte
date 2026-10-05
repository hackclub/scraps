<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { Plus, Trash2, Pencil, Check, X } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';

	interface Macro {
		id: number;
		shortName: string;
		body: string;
		updatedAt: string;
	}

	let macros = $state<Macro[]>([]);
	let loading = $state(true);
	let saving = $state(false);
	let formError = $state<string | null>(null);

	let newShortName = $state('');
	let newBody = $state('');

	let editingId = $state<number | null>(null);
	let editShortName = $state('');
	let editBody = $state('');
	let deleteConfirmId = $state<number | null>(null);

	onMount(async () => {
		const user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}
		await fetchMacros();
	});

	async function fetchMacros() {
		loading = true;
		try {
			const res = await fetch(`${API_URL}/admin/review-macros`, { credentials: 'include' });
			if (res.ok) macros = await res.json();
		} finally {
			loading = false;
		}
	}

	async function send(method: string, path: string, body?: object): Promise<boolean> {
		saving = true;
		formError = null;
		try {
			const res = await fetch(`${API_URL}${path}`, {
				method,
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: body ? JSON.stringify(body) : undefined
			});
			if (!res.ok) {
				const data = await res.json().catch(() => ({}));
				formError = data.error ?? 'Failed to save';
				return false;
			}
			await fetchMacros();
			return true;
		} catch {
			formError = 'Failed to save';
			return false;
		} finally {
			saving = false;
		}
	}

	async function createMacro() {
		if (!newShortName.trim() || !newBody.trim()) {
			formError = 'Short name and text are both required';
			return;
		}
		if (await send('POST', '/admin/review-macros', { shortName: newShortName, body: newBody })) {
			newShortName = '';
			newBody = '';
		}
	}

	function startEdit(m: Macro) {
		editingId = m.id;
		editShortName = m.shortName;
		editBody = m.body;
		formError = null;
	}

	async function saveEdit() {
		if (editingId == null) return;
		if (
			await send('PUT', `/admin/review-macros/${editingId}`, {
				shortName: editShortName,
				body: editBody
			})
		) {
			editingId = null;
		}
	}

	async function deleteMacro(id: number) {
		if (await send('DELETE', `/admin/review-macros/${id}`)) deleteConfirmId = null;
	}
</script>

<svelte:head>
	<title>macros - admin - scraps</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-2 text-4xl font-bold md:text-5xl">review macros</h1>
	<p class="mb-8 text-gray-600">
		canned feedback for the most common rejection reasons. reviewers insert them into "feedback for
		author" with one click on the review page.
	</p>

	<div class="mb-8 rounded-2xl border-4 border-black p-6">
		<h2 class="mb-4 text-xl font-bold">new macro</h2>
		<label for="newShortName" class="mb-1 block text-sm font-bold">short name</label>
		<input
			id="newShortName"
			type="text"
			bind:value={newShortName}
			maxlength="40"
			placeholder="e.g. no-demo"
			class="mb-4 w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
		/>
		<label for="newBody" class="mb-1 block text-sm font-bold">full text</label>
		<textarea
			id="newBody"
			bind:value={newBody}
			rows="4"
			maxlength="2000"
			placeholder="What the author sees, e.g. 'Your project needs a working demo link: a deployed site, a video, or a release.'"
			class="mb-4 w-full resize-y rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
		></textarea>
		{#if formError && editingId == null}
			<p class="mb-3 text-sm font-bold text-red-600">{formError}</p>
		{/if}
		<button
			onclick={createMacro}
			disabled={saving}
			class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-5 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
		>
			<Plus size={16} /> add macro
		</button>
	</div>

	{#if loading}
		<p class="text-gray-500">loading…</p>
	{:else if macros.length === 0}
		<p class="text-gray-500">no macros yet</p>
	{:else}
		<div class="space-y-4">
			{#each macros as m (m.id)}
				<div class="rounded-2xl border-4 border-black p-5">
					{#if editingId === m.id}
						<input
							type="text"
							bind:value={editShortName}
							maxlength="40"
							class="mb-3 w-full rounded-lg border-2 border-black px-4 py-2 font-bold focus:border-dashed focus:outline-none"
						/>
						<textarea
							bind:value={editBody}
							rows="4"
							maxlength="2000"
							class="mb-3 w-full resize-y rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						></textarea>
						{#if formError}
							<p class="mb-3 text-sm font-bold text-red-600">{formError}</p>
						{/if}
						<div class="flex gap-2">
							<button
								onclick={saveEdit}
								disabled={saving}
								class="flex cursor-pointer items-center gap-1 rounded-full border-2 border-black bg-black px-4 py-1.5 text-sm font-bold text-white disabled:opacity-50"
							>
								<Check size={14} /> save
							</button>
							<button
								onclick={() => (editingId = null)}
								class="flex cursor-pointer items-center gap-1 rounded-full border-2 border-black px-4 py-1.5 text-sm font-bold hover:border-dashed"
							>
								<X size={14} /> cancel
							</button>
						</div>
					{:else}
						<div class="mb-2 flex items-start justify-between gap-4">
							<span class="rounded-full border-2 border-black px-3 py-1 text-sm font-bold"
								>{m.shortName}</span
							>
							<div class="flex shrink-0 gap-2">
								<button
									onclick={() => startEdit(m)}
									aria-label="edit {m.shortName}"
									class="cursor-pointer rounded-full border-2 border-black p-1.5 hover:border-dashed"
								>
									<Pencil size={14} />
								</button>
								{#if deleteConfirmId === m.id}
									<button
										onclick={() => deleteMacro(m.id)}
										class="cursor-pointer rounded-full border-2 border-red-600 bg-red-600 px-3 py-1 text-xs font-bold text-white"
									>
										confirm delete
									</button>
									<button
										onclick={() => (deleteConfirmId = null)}
										class="cursor-pointer rounded-full border-2 border-black px-3 py-1 text-xs font-bold"
									>
										keep
									</button>
								{:else}
									<button
										onclick={() => (deleteConfirmId = m.id)}
										aria-label="delete {m.shortName}"
										class="cursor-pointer rounded-full border-2 border-black p-1.5 hover:border-dashed"
									>
										<Trash2 size={14} />
									</button>
								{/if}
							</div>
						</div>
						<p class="text-sm whitespace-pre-wrap text-gray-700">{m.body}</p>
					{/if}
				</div>
			{/each}
		</div>
	{/if}
</div>
