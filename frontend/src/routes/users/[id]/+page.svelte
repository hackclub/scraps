<script lang="ts">
	import { onMount } from 'svelte';
	import {
		ArrowLeft,
		Github,
		Clock,
		Package,
		CheckCircle,
		AlertTriangle,
		Heart,
		Flame,
		Origami,
		Pencil,
		Shield,
		X,
		Spool
	} from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { formatHours } from '$lib/utils';
	import { t } from '$lib/i18n';

	let { data } = $props();

	interface Project {
		id: number;
		name: string;
		description: string;
		image: string | null;
		githubUrl: string | null;
		hours: number;
		status: string;
		createdAt: string;
	}

	interface HeartedItem {
		id: number;
		name: string;
		image: string;
		price: number;
	}

	interface Refinement {
		shopItemId: number;
		itemName: string;
		itemImage: string;
		baseProbability: number;
		totalBoost: number;
		effectiveProbability: number;
	}

	interface ProfileUser {
		id: number;
		username: string;
		avatar: string | null;
		role: 'admin' | 'reviewer' | 'creator' | 'member' | 'banned';
		scraps: number;
		scrapsPending?: number;
		createdAt: string;
	}

	interface Stats {
		projectCount: number;
		inProgressCount: number;
		totalHours: number;
	}

	type FilterType = 'all' | 'shipped' | 'in_progress';

	let profileUser = $state<ProfileUser | null>(null);
	let projects = $state<Project[]>([]);
	let heartedItems = $state<HeartedItem[]>([]);
	let refinements = $state<Refinement[]>([]);
	let stats = $state<Stats | null>(null);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let filter = $state<FilterType>('all');
	let isAdmin = $state(false);
	let showRoleModal = $state(false);
	let selectedRole = $state<'admin' | 'reviewer' | 'creator' | 'member' | 'banned'>('member');
	let savingRole = $state(false);

	let filteredProjects = $derived(
		filter === 'all'
			? projects
			: filter === 'in_progress'
				? projects.filter((p) => p.status === 'in_progress' || p.status === 'waiting_for_review')
				: projects.filter((p) => p.status === filter)
	);

	onMount(async () => {
		try {
			const response = await fetch(`${API_URL}/user/profile/${data.id}`, {
				credentials: 'include'
			});
			if (response.ok) {
				const result = await response.json();
				profileUser = result.user;
				projects = result.projects || [];
				heartedItems = result.heartedItems || [];
				refinements = result.refinements || [];
				stats = result.stats;
				isAdmin = result.isAdmin || false;
			} else {
				error = 'User not found';
			}
		} catch (e) {
			console.error('Failed to fetch profile:', e);
			error = 'Failed to load profile';
		} finally {
			loading = false;
		}
	});

	function openRoleModal() {
		if (profileUser) {
			selectedRole = profileUser.role;
			showRoleModal = true;
		}
	}

	async function updateRole() {
		if (!profileUser) return;
		savingRole = true;
		try {
			const response = await fetch(`${API_URL}/admin/users/${profileUser.id}/role`, {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ role: selectedRole })
			});
			if (response.ok) {
				profileUser = { ...profileUser, role: selectedRole };
				showRoleModal = false;
			} else {
				console.error('Failed to update role');
			}
		} catch (e) {
			console.error('Failed to update role:', e);
		} finally {
			savingRole = false;
		}
	}

	function getRoleColor(role: string): string {
		switch (role) {
			case 'admin':
				return 'bg-red-100 text-red-700 border-red-300';
			case 'creator':
				return 'bg-purple-100 text-purple-700 border-purple-300';
			case 'reviewer':
				return 'bg-purple-100 text-purple-700 border-purple-300';
			case 'banned':
				return 'bg-gray-100 text-gray-700 border-gray-300';
			default:
				return 'bg-blue-100 text-blue-700 border-blue-300';
		}
	}
</script>

<svelte:head>
	<title>{profileUser?.username || 'profile'} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<a
		href="/leaderboard"
		class="mb-8 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
	>
		<ArrowLeft size={20} />
		{$t.profile.backToLeaderboard}
	</a>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.profile.loading}</div>
	{:else if error}
		<div class="py-12 text-center text-gray-500">{error}</div>
	{:else if profileUser}
		<!-- User Header -->
		<div class="mb-6 rounded-2xl border-4 border-black p-4 sm:p-6">
			<div class="flex flex-col items-center gap-4 sm:flex-row sm:items-start sm:gap-6">
				{#if profileUser.avatar}
					<img
						src={profileUser.avatar}
						alt=""
						class="h-16 w-16 shrink-0 rounded-full border-4 border-black sm:h-20 sm:w-20"
					/>
				{:else}
					<div
						class="h-16 w-16 shrink-0 rounded-full border-4 border-black bg-gray-200 sm:h-20 sm:w-20"
					></div>
				{/if}
				<div class="min-w-0 flex-1 text-center sm:text-left">
					<div
						class="mb-1 flex flex-wrap items-center justify-center gap-2 sm:mb-2 sm:justify-start"
					>
						<h1 class="truncate text-2xl font-bold sm:text-3xl">
							{profileUser.username || 'unknown'}
						</h1>
						<span
							class="rounded-full border px-2 py-0.5 text-xs font-bold {getRoleColor(
								profileUser.role
							)}"
						>
							{$t.profile.roles[profileUser.role]}
						</span>
						{#if isAdmin}
							<button
								onclick={openRoleModal}
								class="flex cursor-pointer items-center gap-1 rounded-full border-2 border-black px-2 py-0.5 text-xs font-bold transition-all hover:border-dashed"
							>
								<Pencil size={12} />
								{$t.profile.editRole}
							</button>
							<a
								href="/admin/users/{profileUser.id}"
								class="flex cursor-pointer items-center gap-1 rounded-full border-2 border-black px-2 py-0.5 text-xs font-bold transition-all hover:border-dashed"
							>
								<Shield size={12} />
								{$t.admin.adminUserPage}
							</a>
						{/if}
					</div>
					<p class="text-sm text-gray-500">
						{$t.profile.joined}
						{new Date(profileUser.createdAt).toLocaleDateString()}
					</p>
				</div>
				<div class="shrink-0 text-center sm:text-right">
					<div class="flex items-center justify-center gap-2 sm:justify-end">
						<Spool size={28} />
						<p class="text-3xl font-bold sm:text-4xl">{profileUser.scraps}</p>
					</div>
					{#if profileUser.scrapsPending && profileUser.scrapsPending > 0}
						<p class="text-sm text-gray-400">+{profileUser.scrapsPending} pending</p>
					{/if}
					<p class="text-sm text-gray-500">{$t.profile.scraps}</p>
				</div>
			</div>
		</div>

		<!-- Stats -->
		{#if stats}
			<div class="mb-6 grid grid-cols-3 gap-2 sm:gap-4">
				<div class="rounded-2xl border-4 border-black p-2 text-center sm:p-4">
					<p class="text-xl font-bold text-green-600 sm:text-3xl">{stats.projectCount}</p>
					<p class="text-xs text-gray-500 sm:text-sm">{$t.profile.shipped}</p>
				</div>
				<div class="rounded-2xl border-4 border-black p-2 text-center sm:p-4">
					<p class="text-xl font-bold text-yellow-600 sm:text-3xl">{stats.inProgressCount}</p>
					<p class="text-xs text-gray-500 sm:text-sm">{$t.profile.inProgress}</p>
				</div>
				<div class="rounded-2xl border-4 border-black p-2 text-center sm:p-4">
					<p class="text-xl font-bold sm:text-3xl">{formatHours(stats.totalHours)}h</p>
					<p class="text-xs text-gray-500 sm:text-sm">{$t.profile.totalHours}</p>
				</div>
			</div>
		{/if}

		<!-- Projects -->
		<div class="rounded-2xl border-4 border-black p-4 sm:p-6">
			<div class="mb-4 flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
				<div class="flex items-center gap-2">
					<Origami size={20} />
					<h2 class="text-xl font-bold">{$t.profile.projects} ({filteredProjects.length})</h2>
				</div>
				<div class="flex gap-2 overflow-x-auto">
					<button
						onclick={() => (filter = 'all')}
						class="shrink-0 cursor-pointer rounded-xl border-4 border-black px-3 py-1.5 text-xs font-bold transition-all duration-200 sm:px-4 sm:py-2 sm:text-sm {filter ===
						'all'
							? 'bg-black text-white'
							: 'hover:border-dashed'}"
					>
						{$t.profile.all}
					</button>
					<button
						onclick={() => (filter = 'shipped')}
						class="shrink-0 cursor-pointer rounded-xl border-4 border-black px-3 py-1.5 text-xs font-bold transition-all duration-200 sm:px-4 sm:py-2 sm:text-sm {filter ===
						'shipped'
							? 'bg-black text-white'
							: 'hover:border-dashed'}"
					>
						{$t.profile.shipped}
					</button>
					<button
						onclick={() => (filter = 'in_progress')}
						class="shrink-0 cursor-pointer rounded-xl border-4 border-black px-3 py-1.5 text-xs font-bold transition-all duration-200 sm:px-4 sm:py-2 sm:text-sm {filter ===
						'in_progress'
							? 'bg-black text-white'
							: 'hover:border-dashed'}"
					>
						{$t.profile.inProgress}
					</button>
				</div>
			</div>
			{#if filteredProjects.length === 0}
				<p class="text-gray-500">{$t.profile.noProjectsFound}</p>
			{:else}
				<div class="grid gap-4">
					{#each filteredProjects as project}
						<a
							href="/projects/{project.id}"
							class="block cursor-pointer rounded-lg border-2 border-black p-4 transition-all duration-200 hover:border-dashed"
						>
							<div class="flex gap-4">
								{#if project.image}
									<img
										src={project.image}
										alt={project.name}
										class="h-24 w-24 shrink-0 rounded-lg border-2 border-black object-cover"
									/>
								{:else}
									<div
										class="flex h-24 w-24 shrink-0 items-center justify-center rounded-lg border-2 border-black bg-gray-100"
									>
										<Package size={32} class="text-gray-400" />
									</div>
								{/if}
								<div class="min-w-0 flex-1">
									<div class="mb-1 flex items-center gap-2">
										<h3 class="text-lg font-bold">{project.name}</h3>
										{#if project.status === 'shipped'}
											<span
												class="flex items-center gap-1 rounded-full border border-green-600 bg-green-100 px-2 py-0.5 text-xs font-bold text-green-700"
											>
												<CheckCircle size={12} />
												{$t.profile.shipped}
											</span>
										{:else if project.status === 'waiting_for_review'}
											<span
												class="flex items-center gap-1 rounded-full border border-blue-600 bg-blue-100 px-2 py-0.5 text-xs font-bold text-blue-700"
											>
												<Clock size={12} />
												{$t.profile.underReview}
											</span>
										{:else}
											<span
												class="flex items-center gap-1 rounded-full border border-yellow-600 bg-yellow-100 px-2 py-0.5 text-xs font-bold text-yellow-700"
											>
												<AlertTriangle size={12} />
												{$t.profile.inProgress}
											</span>
										{/if}
									</div>
									<p class="mb-2 line-clamp-2 text-sm text-gray-600">{project.description}</p>
									<div class="flex items-center gap-4 text-sm text-gray-500">
										<span class="flex items-center gap-1">
											<Clock size={14} />
											{formatHours(project.hours)}h
										</span>
										{#if project.githubUrl}
											<span
												onclick={(e) => {
													e.preventDefault();
													e.stopPropagation();
													window.open(project.githubUrl!, '_blank');
												}}
												onkeydown={(e) =>
													e.key === 'Enter' && window.open(project.githubUrl!, '_blank')}
												role="link"
												tabindex="0"
												class="flex cursor-pointer items-center gap-1 transition-colors hover:text-black"
											>
												<Github size={14} />
												{$t.profile.github}
											</span>
										{/if}
									</div>
								</div>
							</div>
						</a>
					{/each}
				</div>
			{/if}
		</div>

		<!-- Hearted Shop Items -->
		{#if heartedItems.length > 0}
			<div class="mt-6 rounded-2xl border-4 border-black p-6">
				<div class="mb-4 flex items-center gap-2">
					<Heart size={20} class="fill-red-500 text-red-500" />
					<h2 class="text-xl font-bold">{$t.profile.wishlist} ({heartedItems.length})</h2>
				</div>
				<div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
					{#each heartedItems as item}
						<a
							href="/shop"
							class="cursor-pointer rounded-2xl border-4 border-black p-3 transition-all duration-200 hover:border-dashed"
						>
							<img src={item.image} alt={item.name} class="mb-2 h-20 w-full object-contain" />
							<h3 class="truncate text-sm font-bold">{item.name}</h3>
							<p class="text-xs text-gray-500">{item.price} scraps</p>
						</a>
					{/each}
				</div>
			</div>
		{/if}

		<!-- Refinements -->
		{#if refinements.length > 0}
			<div class="mt-6 rounded-2xl border-4 border-black p-6">
				<div class="mb-4 flex items-center gap-2">
					<Flame size={20} class="text-orange-500" />
					<h2 class="text-xl font-bold">{$t.profile.refinements}</h2>
				</div>
				{#if refinements.length === 0}
					<p class="py-4 text-center text-gray-500">{$t.profile.noRefinements}</p>
				{:else}
					<div class="space-y-3">
						{#each refinements.sort((a, b) => b.totalBoost - a.totalBoost) as refinement}
							{@const maxBoost = Math.max(...refinements.map((r) => r.totalBoost))}
							{@const barWidth = maxBoost > 0 ? (refinement.totalBoost / maxBoost) * 100 : 0}
							<div class="relative">
								<div
									class="flex h-10 items-center justify-between rounded-lg border-2 border-black bg-black px-3 text-sm font-bold text-white"
									style="width: {Math.max(barWidth, 20)}%;"
								>
									<span class="truncate">{refinement.itemName}</span>
									<span class="ml-2 shrink-0">+{refinement.totalBoost}%</span>
								</div>
							</div>
						{/each}
					</div>
				{/if}
			</div>
		{/if}
	{/if}
</div>

<!-- Role Edit Modal -->
{#if showRoleModal && profileUser}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (showRoleModal = false)}
		onkeydown={(e) => e.key === 'Escape' && (showRoleModal = false)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<div class="mb-4 flex items-center justify-between">
				<div class="flex items-center gap-2">
					<Shield size={20} />
					<h2 class="text-xl font-bold">{$t.profile.changeRole}</h2>
				</div>
				<button
					onclick={() => (showRoleModal = false)}
					class="cursor-pointer rounded-lg p-1 transition-colors hover:bg-gray-100"
				>
					<X size={20} />
				</button>
			</div>

			<p class="mb-4 text-gray-600">
				{profileUser.username}
			</p>

			<div class="mb-6 space-y-2">
				{#each ['admin', 'reviewer', 'member', 'banned'] as role}
					<button
						onclick={() => (selectedRole = role as typeof selectedRole)}
						class="flex w-full cursor-pointer items-center gap-3 rounded-xl border-4 px-4 py-3 text-left font-bold transition-all {selectedRole ===
						role
							? 'border-black bg-black text-white'
							: 'border-black hover:border-dashed'}"
					>
						<span
							class="h-3 w-3 rounded-full {role === 'admin'
								? 'bg-red-500'
								: role === 'reviewer'
									? 'bg-purple-500'
									: role === 'banned'
										? 'bg-gray-500'
										: 'bg-blue-500'}"
						></span>
						{$t.profile.roles[role as keyof typeof $t.profile.roles]}
					</button>
				{/each}
			</div>

			<div class="flex gap-3">
				<button
					onclick={() => (showRoleModal = false)}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={updateRole}
					disabled={savingRole || selectedRole === profileUser.role}
					class="flex-1 cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
				>
					{savingRole ? $t.common.saving : $t.profile.updateRole}
				</button>
			</div>
		</div>
	</div>
{/if}
