<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { ArrowLeft, Github, Globe, Trash2, ClipboardList, RotateCcw } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { formatHours } from '$lib/utils';

	let { data } = $props();

	interface Project {
		id: number;
		name: string;
		description: string;
		image: string | null;
		githubUrl: string | null;
		playableUrl: string | null;
		hours: number;
		tier: number;
		status: string;
		scrapsAwarded: number;
		views: number;
		createdAt: string;
	}
	interface Owner {
		id: number;
		username: string | null;
		avatar: string | null;
	}

	let project = $state<Project | null>(null);
	let owner = $state<Owner | null>(null);
	let isDeleted = $state(false);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let showDeleteConfirm = $state(false);
	let deleting = $state(false);
	let restoring = $state(false);

	async function load() {
		const res = await fetch(`${API_URL}/projects/${data.id}`, { credentials: 'include' });
		if (!res.ok) throw new Error('Project not found');
		const body = await res.json();
		if (body.error) throw new Error(body.error);
		project = body.project;
		owner = body.owner;
		isDeleted = body.isDeleted;
	}

	onMount(async () => {
		const user = await getUser();
		if (!user || !['admin', 'creator'].includes(user.role)) {
			goto(`/projects/${data.id}`, { replaceState: true });
			return;
		}
		try {
			await load();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load project';
		} finally {
			loading = false;
		}
	});

	async function handleDelete() {
		if (deleting) return;
		deleting = true;
		error = null;
		try {
			const res = await fetch(`${API_URL}/projects/${data.id}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			const body = await res.json().catch(() => ({}));
			if (!res.ok || body.error) {
				error = body.error || 'Failed to delete project';
			} else {
				await load();
			}
		} catch {
			error = 'Failed to delete project';
		} finally {
			deleting = false;
			showDeleteConfirm = false;
		}
	}

	async function handleRestore() {
		if (restoring) return;
		restoring = true;
		error = null;
		try {
			const res = await fetch(`${API_URL}/projects/${data.id}/restore`, {
				method: 'POST',
				credentials: 'include'
			});
			const body = await res.json().catch(() => ({}));
			if (!res.ok || body.error) {
				error = body.error || 'Failed to restore project';
			} else {
				await load();
			}
		} catch {
			error = 'Failed to restore project';
		} finally {
			restoring = false;
		}
	}
</script>

<svelte:head>
	<title>{project?.name ?? 'project'} - scraps admin</title>
</svelte:head>

<div class="mx-auto max-w-2xl px-6 pt-24 pb-24 md:px-12">
	<a href="/admin" class="mb-6 inline-flex items-center gap-2 font-bold hover:underline">
		<ArrowLeft size={18} /> admin
	</a>

	{#if loading}
		<p class="text-gray-500">loading…</p>
	{:else if error && !project}
		<p class="rounded-xl border-2 border-red-500 bg-red-100 p-4 text-red-700">{error}</p>
	{:else if project}
		<div class="rounded-2xl border-4 border-black bg-white p-6">
			<div class="mb-4 flex items-start justify-between gap-4">
				<div>
					<h1 class="text-3xl font-bold">{project.name}</h1>
					<p class="mt-1 flex items-center gap-2 text-sm text-gray-500">
						{#if owner?.avatar}<img src={owner.avatar} alt="" class="h-5 w-5 rounded-full" />{/if}
						{owner?.username ?? 'unknown'} · project #{project.id}
					</p>
				</div>
				<div class="flex shrink-0 flex-col items-end gap-1">
					<span class="rounded-full border-2 border-black px-3 py-1 text-xs font-bold"
						>{project.status}</span
					>
					{#if isDeleted}
						<span class="rounded-full bg-red-600 px-3 py-1 text-xs font-bold text-white">deleted</span>
					{/if}
				</div>
			</div>

			{#if project.image}
				<img
					src={project.image}
					alt=""
					class="mb-4 max-h-64 w-full rounded-xl border-2 border-black object-cover"
				/>
			{/if}

			<p class="mb-4 whitespace-pre-wrap text-gray-700">{project.description}</p>

			<div class="mb-4 flex flex-wrap gap-3 text-sm">
				<span class="rounded-full bg-gray-100 px-3 py-1 font-bold">{formatHours(project.hours)}h</span>
				<span class="rounded-full bg-gray-100 px-3 py-1 font-bold">tier {project.tier}</span>
				<span class="rounded-full bg-gray-100 px-3 py-1 font-bold">{project.scrapsAwarded} scraps</span>
				<span class="rounded-full bg-gray-100 px-3 py-1 font-bold">{project.views} views</span>
			</div>

			<div class="flex flex-wrap gap-3">
				{#if project.githubUrl}
					<a
						href={project.githubUrl}
						target="_blank"
						rel="noopener noreferrer"
						class="flex items-center gap-2 rounded-full border-2 border-black px-4 py-2 text-sm font-bold hover:border-dashed"
					>
						<Github size={16} /> repo
					</a>
				{/if}
				{#if project.playableUrl}
					<a
						href={project.playableUrl}
						target="_blank"
						rel="noopener noreferrer"
						class="flex items-center gap-2 rounded-full border-2 border-black px-4 py-2 text-sm font-bold hover:border-dashed"
					>
						<Globe size={16} /> demo
					</a>
				{/if}
				{#if project.status === 'waiting_for_review'}
					<a
						href="/admin/reviews/{project.id}"
						class="flex items-center gap-2 rounded-full bg-black px-4 py-2 text-sm font-bold text-white hover:bg-gray-800"
					>
						<ClipboardList size={16} /> open review
					</a>
				{/if}
			</div>
		</div>

		{#if error}
			<p class="mt-4 rounded-xl border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
				{error}
			</p>
		{/if}

		{#if isDeleted}
			<button
				onclick={handleRestore}
				disabled={restoring}
				class="mt-6 flex items-center gap-2 rounded-full border-4 border-black px-5 py-2 font-bold transition-all hover:border-dashed disabled:opacity-50"
			>
				<RotateCcw size={18} /> {restoring ? 'restoring…' : 'restore project'}
			</button>
		{:else}
			<button
				onclick={() => (showDeleteConfirm = true)}
				class="mt-6 flex items-center gap-2 rounded-full border-4 border-red-500 px-5 py-2 font-bold text-red-600 transition-all hover:border-dashed hover:bg-red-50"
			>
				<Trash2 size={18} /> delete project
			</button>
		{/if}
	{/if}
</div>

{#if showDeleteConfirm && project}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-6"
		onclick={(e) => e.target === e.currentTarget && (showDeleteConfirm = false)}
		onkeydown={(e) => e.key === 'Escape' && (showDeleteConfirm = false)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-lg rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">delete this project?</h2>
			<p class="mb-6 text-gray-700">
				this permanently removes <span class="font-bold">{project.name}</span> by
				{owner?.username ?? 'unknown'}. this can't be undone.
			</p>
			<div class="flex gap-4">
				<button
					onclick={() => (showDeleteConfirm = false)}
					disabled={deleting}
					class="flex-1 rounded-full border-4 border-black px-4 py-3 font-bold hover:border-dashed disabled:opacity-50"
				>
					cancel
				</button>
				<button
					onclick={handleDelete}
					disabled={deleting}
					class="flex flex-1 items-center justify-center gap-2 rounded-full border-4 border-red-600 bg-red-600 px-4 py-3 font-bold text-white hover:bg-red-700 disabled:opacity-50"
				>
					<Trash2 size={18} /> {deleting ? 'deleting…' : 'delete project'}
				</button>
			</div>
		</div>
	</div>
{/if}
