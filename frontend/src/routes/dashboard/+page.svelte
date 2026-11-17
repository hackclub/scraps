<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import ProjectPlaceholder from '$lib/components/ProjectPlaceholder.svelte';
	import NewsBox from '$lib/components/NewsBox.svelte';
	import StreakCard from '$lib/components/StreakCard.svelte';
	import CreateProjectModal from '$lib/components/CreateProjectModal.svelte';
	import { getUser, requireLogin } from '$lib/auth-client';
	import { projectsStore, fetchProjects, addProject } from '$lib/stores';
	import { formatHours } from '$lib/utils';
	import { t } from '$lib/i18n';
	import { Plus } from '@lucide/svelte';

	const greetingPhrases = $derived(Object.values($t.dashboard.greetings));
	const helloSeed = Math.random();
	const phraseSeed = Math.random();
	let randomHello = $derived(
		$t.dashboard.hellos[Math.floor(helloSeed * $t.dashboard.hellos.length)]
	);
	let randomPhrase = $derived(greetingPhrases[Math.floor(phraseSeed * greetingPhrases.length)]);

	let showCreateModal = $state(false);
	let user = $state<Awaited<ReturnType<typeof getUser>>>(null);
	let canCreateProject = $derived(!!user);
	onMount(async () => {
		const userData = await getUser();
		if (!userData) {
			requireLogin();
			return;
		}
		user = userData;
		fetchProjects();
	});
</script>

<svelte:head>
	<title>dashboard - scraps</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12 md:pt-32">
	<!-- Greeting -->
	<div class="mb-8 flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
		<div class="min-w-0">
			{#if user}
				<h1 class="mb-2 text-4xl font-bold md:text-5xl">
					{randomHello.replace(
						'{name}',
						(user.username || 'friend').trim().split(/\s+/)[0].toLocaleLowerCase()
					)}
				</h1>
				<p class="text-lg text-gray-600">{randomPhrase}</p>
			{/if}
		</div>
		<NewsBox />
	</div>

	<!-- Projects Section -->
	<div class="mb-8">
		<div class="scrollbar-black flex gap-6 overflow-x-auto pb-4">
			{#if canCreateProject}
				<a
					href="/dashboard"
					onclick={(e) => {
						e.preventDefault();
						showCreateModal = true;
					}}
					data-tutorial="new-project"
					class="flex h-64 w-80 shrink-0 cursor-pointer flex-col items-center justify-center gap-3 rounded-2xl border-4 border-black bg-white transition-all hover:border-dashed"
				>
					<Plus size={48} class="text-gray-400" />
					<span class="text-lg font-bold text-gray-400">{$t.dashboard.newProject}</span>
				</a>
			{/if}
			{#each $projectsStore as project (project.id)}
				<a
					href="/projects/{project.id}"
					class="group relative flex h-64 w-80 shrink-0 cursor-pointer flex-col overflow-hidden rounded-2xl border-4 border-black bg-white transition-all hover:border-dashed"
				>
					<div class="flex-1 overflow-hidden">
						{#if project.image}
							<img src={project.image} alt={project.name} class="h-full w-full object-cover" />
						{:else}
							<ProjectPlaceholder seed={project.id} />
						{/if}
					</div>
					<div class="border-t-2 border-black bg-white px-4 py-3">
						<div class="mb-1 flex items-center justify-between">
							<span class="truncate text-lg font-bold">{project.name}</span>
							<span class="shrink-0 text-sm text-gray-500"
								>{formatHours(project.hoursOverride ?? project.hours)}h</span
							>
						</div>
						<div class="flex items-center justify-end">
							<span
								class="rounded-full px-2 py-0.5 text-xs {project.status === 'shipped'
									? 'bg-green-100'
									: project.status === 'waiting_for_review'
										? 'bg-yellow-100'
										: 'bg-gray-100'}"
							>
								{project.status.replace(/_/g, ' ')}
							</span>
						</div>
					</div>
				</a>
			{/each}
		</div>
	</div>

	<StreakCard />
</div>

{#if canCreateProject}
	<CreateProjectModal
		open={showCreateModal}
		onClose={() => (showCreateModal = false)}
		onCreated={(project) => {
			addProject(project);
			showCreateModal = false;
			goto(`/projects/${project.id}`);
		}}
	/>
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
