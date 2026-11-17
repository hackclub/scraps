<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { getUser, requireLogin } from '$lib/auth-client';
	import ProjectPlaceholder from '$lib/components/ProjectPlaceholder.svelte';
	import NewsBox from '$lib/components/NewsBox.svelte';
	import StreakCard from '$lib/components/StreakCard.svelte';
	import { Plus } from '@lucide/svelte';

	const projects = [
		{ id: 101, name: 'tiny synth', hours: 12.4, status: 'shipped' },
		{
			id: 102,
			name: 'plant watering bot',
			hours: 7.1,
			status: 'waiting_for_review',
			queuePosition: 4,
			queueTotal: 23
		},
		{ id: 103, name: 'pixel weather', hours: 3.5, status: 'in_progress' },
		{ id: 104, name: 'chat app', hours: 18.2, status: 'rejected' }
	];

	let username = $state('');
	let allowed = $state(false);

	onMount(async () => {
		const u = await getUser();
		if (!u) {
			requireLogin();
			return;
		}
		if (u.role !== 'admin') {
			goto('/dashboard');
			return;
		}
		username = u.username ?? '';
		allowed = true;
	});
</script>

<svelte:head>
	<title>dashboard (demo) - scraps</title>
</svelte:head>

{#if allowed}
	<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12 md:pt-32">
		<p class="mb-4 text-xs text-gray-400">demo · projects are fake</p>

		<div class="mb-8 flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
			<div class="min-w-0">
				<h1 class="mb-2 text-4xl font-bold md:text-5xl">hello {username}</h1>
				<p class="text-lg text-gray-600">ready to scrap?</p>
			</div>
			<NewsBox />
		</div>

		<div class="mb-8">
			<div class="scrollbar-black flex gap-6 overflow-x-auto pb-4">
				<div
					class="flex h-64 w-80 shrink-0 cursor-pointer flex-col items-center justify-center gap-3 rounded-2xl border-4 border-black bg-white transition-all hover:border-dashed"
				>
					<Plus size={48} class="text-gray-400" />
					<span class="text-lg font-bold text-gray-400">new project</span>
				</div>
				{#each projects as project (project.id)}
					<div
						class="relative flex h-64 w-80 shrink-0 flex-col overflow-hidden rounded-2xl border-4 border-black bg-white transition-all hover:border-dashed"
					>
						<div class="flex-1 overflow-hidden">
							<ProjectPlaceholder seed={project.id} />
						</div>
						<div class="border-t-2 border-black bg-white px-4 py-3">
							<div class="mb-1 flex items-center justify-between">
								<span class="truncate text-lg font-bold">{project.name}</span>
								<span class="shrink-0 text-sm text-gray-500">{project.hours}h</span>
							</div>
							<div class="flex items-center justify-end">
								<span
									class="rounded-full px-2 py-0.5 text-xs {project.status === 'shipped'
										? 'bg-green-100'
										: project.status === 'waiting_for_review'
											? 'bg-yellow-100'
											: project.status === 'rejected'
												? 'bg-red-100 text-red-700'
												: 'bg-gray-100'} flex items-center gap-1"
								>
									{project.status.replace(/_/g, ' ')}
									{#if project.queuePosition && project.queueTotal}
										<span class="h-3 border-l-2 border-yellow-600"></span>
										#{project.queuePosition}/{project.queueTotal}
									{/if}
								</span>
							</div>
						</div>
					</div>
				{/each}
			</div>
		</div>

		<StreakCard demo />
	</div>
{/if}

<style>
	.scrollbar-black {
		scrollbar-width: thin;
		scrollbar-color: black transparent;
	}
	.scrollbar-black::-webkit-scrollbar {
		height: 4px;
	}
	.scrollbar-black::-webkit-scrollbar-track {
		background: transparent;
	}
	.scrollbar-black::-webkit-scrollbar-thumb {
		background-color: black;
		border-radius: 9999px;
	}
</style>
