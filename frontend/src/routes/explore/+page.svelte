<script lang="ts">
	import { onMount } from 'svelte';
	import { Search, Eye, X } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { formatHours } from '$lib/utils';
	import ProjectPlaceholder from '$lib/components/ProjectPlaceholder.svelte';
	import { t } from '$lib/i18n';

	interface ExploreProject {
		id: number;
		name: string;
		description: string;
		image: string | null;
		hours: number;
		tier: number;
		status: string;
		views: number;
		username: string | null;
	}

	interface Pagination {
		page: number;
		limit: number;
		total: number;
		totalPages: number;
	}

	let projects = $state<ExploreProject[]>([]);
	let pagination = $state<Pagination | null>(null);
	let loading = $state(true);
	let error = $state<string | null>(null);

	let searchQuery = $state('');
	let selectedTier = $state<number | null>(null);
	let selectedStatus = $state<string | null>(null);
	let sortBy = $state<'default' | 'views' | 'random'>('default');
	let currentPage = $state(1);

	let searchTimeout: ReturnType<typeof setTimeout>;

	const TIERS = [1, 2, 3, 4];

	async function fetchProjects() {
		loading = true;
		error = null;

		try {
			const params = new URLSearchParams();
			params.set('page', currentPage.toString());
			params.set('limit', '18');
			if (searchQuery.trim()) params.set('search', searchQuery.trim());
			if (selectedTier) params.set('tier', selectedTier.toString());
			if (selectedStatus) params.set('status', selectedStatus);
			if (sortBy !== 'default') params.set('sortBy', sortBy);

			const response = await fetch(`${API_URL}/projects/explore?${params}`, {
				credentials: 'include'
			});

			if (!response.ok) throw new Error('Failed to fetch projects');

			const data = await response.json();
			projects = data.data;
			pagination = data.pagination;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load projects';
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		fetchProjects();
	});

	function handleSearch() {
		clearTimeout(searchTimeout);
		searchTimeout = setTimeout(() => {
			currentPage = 1;
			fetchProjects();
		}, 300);
	}

	function toggleTier(tier: number) {
		selectedTier = selectedTier === tier ? null : tier;
		currentPage = 1;
		fetchProjects();
	}

	function toggleStatus(status: string) {
		selectedStatus = selectedStatus === status ? null : status;
		currentPage = 1;
		fetchProjects();
	}

	function setSortBy(value: 'default' | 'views' | 'random') {
		sortBy = value;
		currentPage = 1;
		fetchProjects();
	}

	function goToPage(page: number) {
		currentPage = page;
		fetchProjects();
	}
</script>

<svelte:head>
	<title>{$t.explore.explore} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-8 text-4xl font-bold md:text-5xl">{$t.explore.explore}</h1>

	<!-- Search & Filters -->
	<div class="mb-8 space-y-3">
		<!-- Search -->
		<div class="relative">
			<Search size={20} class="absolute top-1/2 left-4 -translate-y-1/2 text-gray-400" />
			<input
				type="text"
				bind:value={searchQuery}
				oninput={handleSearch}
				placeholder={$t.explore.searchPlaceholder}
				class="w-full rounded-full border-4 border-black py-3 pr-4 pl-12 focus:border-dashed focus:outline-none"
			/>
		</div>

		<!-- Tier filters -->
		<div class="flex flex-wrap items-center gap-2">
			<span class="mr-2 self-center text-sm font-bold">{$t.explore.tier}</span>
			{#each TIERS as tier}
				<button
					onclick={() => toggleTier(tier)}
					class="cursor-pointer rounded-xl border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 sm:px-4 sm:py-2 {selectedTier ===
					tier
						? 'bg-black text-white'
						: 'hover:border-dashed'}"
				>
					{tier}
				</button>
			{/each}
		</div>

		<!-- Status filters -->
		<div class="flex flex-wrap items-center gap-2">
			<span class="mr-2 self-center text-sm font-bold">{$t.explore.status}</span>
			<button
				onclick={() => toggleStatus('shipped')}
				class="cursor-pointer rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 sm:px-4 sm:py-2 {selectedStatus ===
				'shipped'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{$t.explore.shipped}
			</button>
			<button
				onclick={() => toggleStatus('in_progress')}
				class="cursor-pointer rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 sm:px-4 sm:py-2 {selectedStatus ===
				'in_progress'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{$t.explore.inProgress}
			</button>
		</div>

		<!-- Sort options -->
		<div class="flex flex-wrap items-center gap-2">
			<span class="mr-2 self-center text-sm font-bold">{$t.explore.sort}</span>
			<button
				onclick={() => setSortBy('default')}
				class="cursor-pointer rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 sm:px-4 sm:py-2 {sortBy ===
				'default'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{$t.explore.recent}
			</button>
			<button
				onclick={() => setSortBy('views')}
				class="cursor-pointer rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 sm:px-4 sm:py-2 {sortBy ===
				'views'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{$t.explore.mostViewed}
			</button>
			<button
				onclick={() => setSortBy('random')}
				class="cursor-pointer rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 sm:px-4 sm:py-2 {sortBy ===
				'random'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{$t.explore.random}
			</button>
			{#if selectedTier || selectedStatus || sortBy !== 'default'}
				<button
					onclick={() => {
						selectedTier = null;
						selectedStatus = null;
						sortBy = 'default';
						currentPage = 1;
						fetchProjects();
					}}
					class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 hover:border-dashed sm:px-4 sm:py-2"
				>
					<X size={16} />
					{$t.explore.clear}
				</button>
			{/if}
		</div>
	</div>

	<!-- Results -->
	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.explore.loadingProjects}</div>
	{:else if error}
		<div class="py-12 text-center text-red-600">{error}</div>
	{:else if projects.length === 0}
		<div class="rounded-2xl border-4 border-dashed border-gray-300 p-12 text-center">
			<p class="text-lg text-gray-500">{$t.explore.noProjectsFound}</p>
			<p class="mt-2 text-sm text-gray-400">{$t.explore.tryAdjustingFilters}</p>
		</div>
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
			{#each projects as project}
				<a
					href="/projects/{project.id}"
					class="flex cursor-pointer flex-col overflow-hidden rounded-2xl border-4 border-black bg-white transition-all duration-200 hover:border-dashed"
				>
					<div class="h-40 overflow-hidden">
						{#if project.image}
							<img src={project.image} alt={project.name} class="h-full w-full object-cover" />
						{:else}
							<ProjectPlaceholder seed={project.id} />
						{/if}
					</div>
					<div class="flex flex-1 flex-col p-4">
						<div class="mb-2 flex items-start justify-between gap-2">
							<h3 class="truncate text-lg font-bold">{project.name}</h3>
							<span
								class="shrink-0 rounded-full px-2 py-0.5 text-xs {project.status === 'shipped'
									? 'bg-green-100'
									: project.status === 'waiting_for_review'
										? 'bg-blue-100'
										: 'bg-gray-100'}"
							>
								{project.status === 'waiting_for_review'
									? 'under review'
									: project.status.replace(/_/g, ' ')}
							</span>
						</div>
						<p class="line-clamp-2 flex-1 text-sm text-gray-600">{project.description}</p>
						<div class="mt-3 flex items-center justify-between text-sm">
							<span class="text-gray-500"
								>{$t.explore.by} {project.username || $t.explore.anonymous}</span
							>
							<div class="flex items-center gap-3">
								<span class="text-gray-500">{formatHours(project.hours)}h</span>
								<span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs">tier {project.tier}</span
								>
								<span class="flex items-center gap-1 text-gray-400">
									<Eye size={14} />
									{project.views}
								</span>
							</div>
						</div>
					</div>
				</a>
			{/each}
		</div>

		<!-- Pagination -->
		{#if pagination && pagination.totalPages > 1}
			<div class="mt-8 flex justify-center gap-2">
				<button
					onclick={() => goToPage(currentPage - 1)}
					disabled={currentPage === 1}
					class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{$t.explore.prev}
				</button>
				<span class="self-center px-4 py-2 font-bold">
					{currentPage} / {pagination.totalPages}
				</span>
				<button
					onclick={() => goToPage(currentPage + 1)}
					disabled={currentPage === pagination.totalPages}
					class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{$t.explore.next}
				</button>
			</div>
		{/if}
	{/if}
</div>
