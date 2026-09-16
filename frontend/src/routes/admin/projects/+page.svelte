<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { ChevronLeft, ChevronRight, Search } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { formatHours } from '$lib/utils';
	import { t } from '$lib/i18n';

	interface AdminProject {
		id: number;
		name: string;
		status: string;
		tier: number;
		hours: number;
		scrapsAwarded: number;
		views: number;
		createdAt: string;
		updatedAt: string;
		userId: number;
		username: string | null;
		avatar: string | null;
	}

	interface Pagination {
		page: number;
		limit: number;
		total: number;
		totalPages: number;
	}

	let user = $state<{ role: string } | null>(null);
	let projects = $state<AdminProject[]>([]);
	let pagination = $state<Pagination | null>(null);
	let loading = $state(true);
	let searchQuery = $state('');
	let statusFilter = $state('');
	let searchTimeout: ReturnType<typeof setTimeout> | null = null;

	const statusOptions = [
		{ value: '', label: 'all statuses' },
		{ value: 'in_progress', label: 'in progress' },
		{ value: 'waiting_for_review', label: 'waiting for review' },
		{ value: 'shipped', label: 'shipped' },
		{ value: 'permanently_rejected', label: 'permanently rejected' }
	];

	onMount(async () => {
		user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'reviewer' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}

		await fetchProjects();
	});

	async function fetchProjects(page = 1, search = searchQuery, status = statusFilter) {
		loading = true;
		try {
			const params = new URLSearchParams({ page: String(page), limit: '20' });
			if (search) params.set('search', search);
			if (status) params.set('status', status);
			const response = await fetch(`${API_URL}/admin/projects?${params}`, {
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				projects = data.data || [];
				pagination = data.pagination;
			}
		} catch (e) {
			console.error('Failed to fetch projects:', e);
		} finally {
			loading = false;
		}
	}

	function handleSearch(e: Event) {
		const value = (e.target as HTMLInputElement).value;
		searchQuery = value;
		if (searchTimeout) clearTimeout(searchTimeout);
		searchTimeout = setTimeout(() => {
			fetchProjects(1, value, statusFilter);
		}, 300);
	}

	function handleStatusChange(e: Event) {
		const value = (e.target as HTMLSelectElement).value;
		statusFilter = value;
		fetchProjects(1, searchQuery, value);
	}

	function goToPage(page: number) {
		fetchProjects(page);
	}

	function getStatusBadge(status: string) {
		switch (status) {
			case 'shipped':
				return { label: 'shipped', class: 'bg-green-100 text-green-700' };
			case 'in_progress':
				return { label: 'in progress', class: 'bg-yellow-100 text-yellow-700' };
			case 'waiting_for_review':
				return { label: 'waiting for review', class: 'bg-yellow-100 text-yellow-700' };
			case 'permanently_rejected':
				return { label: 'rejected', class: 'bg-red-100 text-red-700' };
			default:
				return { label: status.replace(/_/g, ' '), class: 'bg-gray-100 text-gray-700' };
		}
	}
</script>

<svelte:head>
	<title>{$t.nav.projects} - {$t.nav.admin} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-8">
		<h1 class="mb-2 text-4xl font-bold md:text-5xl">{$t.nav.projects}</h1>
		<p class="text-lg text-gray-600">{$t.admin.manageAllProjects}</p>
	</div>

	<div class="mb-6 flex flex-col gap-3 sm:flex-row">
		<div class="relative flex-1">
			<Search size={20} class="absolute top-1/2 left-4 -translate-y-1/2 text-gray-400" />
			<input
				type="text"
				placeholder="search by project id, name, or owner..."
				value={searchQuery}
				oninput={handleSearch}
				class="w-full rounded-full border-4 border-black py-3 pr-4 pl-12 focus:border-dashed focus:outline-none"
			/>
		</div>
		<select
			value={statusFilter}
			onchange={handleStatusChange}
			class="rounded-full border-4 border-black px-4 py-3 font-bold focus:border-dashed focus:outline-none"
		>
			{#each statusOptions as opt (opt.value)}
				<option value={opt.value}>{opt.label}</option>
			{/each}
		</select>
	</div>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if projects.length === 0}
		<p class="rounded-2xl border-4 border-dashed border-gray-300 p-8 text-center text-gray-400">
			no projects match that search
		</p>
	{:else}
		<div class="overflow-x-auto rounded-2xl border-4 border-black">
			<table class="w-full min-w-[760px]">
				<thead>
					<tr class="border-b-4 border-black bg-black text-white">
						<th class="px-4 py-4 text-left font-bold">project</th>
						<th class="px-4 py-4 text-left font-bold">owner</th>
						<th class="px-4 py-4 text-center font-bold">status</th>
						<th class="px-4 py-4 text-center font-bold">tier</th>
						<th class="px-4 py-4 text-center font-bold">hours</th>
						<th class="px-4 py-4 text-center font-bold">scraps</th>
						<th class="px-4 py-4 text-center font-bold">views</th>
						<th class="px-4 py-4 text-right font-bold">actions</th>
					</tr>
				</thead>
				<tbody>
					{#each projects as p (p.id)}
						{@const badge = getStatusBadge(p.status)}
						<tr class="border-b-2 border-black/20 last:border-b-0 hover:bg-gray-50">
							<td class="max-w-64 truncate px-4 py-4 font-bold">{p.name || 'untitled'}</td>
							<td class="px-4 py-4">
								<div class="flex items-center gap-2">
									{#if p.avatar}
										<img
											src={p.avatar}
											alt=""
											class="h-7 w-7 rounded-full border-2 border-black object-cover"
										/>
									{:else}
										<div class="h-7 w-7 rounded-full border-2 border-black bg-gray-200"></div>
									{/if}
									<span>{p.username || 'unknown'}</span>
								</div>
							</td>
							<td class="px-4 py-4 text-center">
								<span class="rounded-full px-3 py-1 text-sm font-bold {badge.class}">
									{badge.label}
								</span>
							</td>
							<td class="px-4 py-4 text-center font-bold">{p.tier}</td>
							<td class="px-4 py-4 text-center">{formatHours(p.hours)}</td>
							<td class="px-4 py-4 text-center font-bold">{p.scrapsAwarded}</td>
							<td class="px-4 py-4 text-center">{p.views}</td>
							<td class="px-4 py-4 text-right">
								<a
									href="/admin/projects/{p.id}"
									class="cursor-pointer rounded-full border-4 border-black px-3 py-1 text-sm font-bold transition-all duration-200 hover:border-dashed"
								>
									{$t.admin.view}
								</a>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>

		{#if pagination && pagination.totalPages > 1}
			<div class="mt-8 flex items-center justify-center gap-4">
				<button
					onclick={() => goToPage(pagination!.page - 1)}
					disabled={pagination.page <= 1}
					class="cursor-pointer rounded-full border-2 border-black p-2 transition-all hover:border-dashed disabled:cursor-not-allowed disabled:opacity-30"
				>
					<ChevronLeft size={20} />
				</button>
				<span class="font-bold">
					{$t.admin.page}
					{pagination.page}
					{$t.admin.of}
					{pagination.totalPages}
				</span>
				<button
					onclick={() => goToPage(pagination!.page + 1)}
					disabled={pagination.page >= pagination.totalPages}
					class="cursor-pointer rounded-full border-2 border-black p-2 transition-all hover:border-dashed disabled:cursor-not-allowed disabled:opacity-30"
				>
					<ChevronRight size={20} />
				</button>
			</div>
		{/if}
	{/if}
</div>
