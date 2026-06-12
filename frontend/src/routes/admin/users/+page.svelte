<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { ChevronLeft, ChevronRight, Search } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';

	interface AdminUser {
		id: number;
		username: string | null;
		email?: string;
		avatar: string | null;
		slackId: string | null;
		scraps: number;
		role: string;
		internalNotes: string | null;
		createdAt: string;
	}

	interface Pagination {
		page: number;
		limit: number;
		total: number;
		totalPages: number;
	}

	interface User {
		id: number;
		username: string;
		email: string;
		avatar: string | null;
		slackId: string | null;
		scraps: number;
		role: string;
	}

	let user = $state<User | null>(null);
	let users = $state<AdminUser[]>([]);
	let pagination = $state<Pagination | null>(null);
	let loading = $state(true);
	let _scraps = $derived(user?.scraps ?? 0);
	let editingUser = $state<AdminUser | null>(null);
	let editingNotes = $state('');
	let editingRole = $state('');
	let saving = $state(false);
	let searchQuery = $state('');
	let searchTimeout: ReturnType<typeof setTimeout> | null = null;

	onMount(async () => {
		user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'reviewer' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}

		await fetchUsers();
	});

	async function fetchUsers(page = 1, search = searchQuery) {
		loading = true;
		try {
			const params = new URLSearchParams({ page: String(page), limit: '20' });
			if (search) params.set('search', search);
			const response = await fetch(`${API_URL}/admin/users?${params}`, {
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				users = data.data || [];
				pagination = data.pagination;
			}
		} catch (e) {
			console.error('Failed to fetch users:', e);
		} finally {
			loading = false;
		}
	}

	function handleSearch(e: Event) {
		const value = (e.target as HTMLInputElement).value;
		searchQuery = value;
		if (searchTimeout) clearTimeout(searchTimeout);
		searchTimeout = setTimeout(() => {
			fetchUsers(1, value);
		}, 300);
	}

	function goToPage(page: number) {
		fetchUsers(page);
	}

	function startEditing(u: AdminUser) {
		editingUser = u;
		editingNotes = u.internalNotes || '';
		editingRole = u.role;
	}

	function cancelEditing() {
		editingUser = null;
		editingNotes = '';
		editingRole = '';
	}

	async function saveChanges() {
		if (!editingUser) return;
		saving = true;

		try {
			// Save notes
			await fetch(`${API_URL}/admin/users/${editingUser.id}/notes`, {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ internalNotes: editingNotes })
			});

			// Save role if admin
			if ((user?.role === 'admin' || user?.role === 'creator') && editingRole !== editingUser.role) {
				await fetch(`${API_URL}/admin/users/${editingUser.id}/role`, {
					method: 'PUT',
					headers: { 'Content-Type': 'application/json' },
					credentials: 'include',
					body: JSON.stringify({ role: editingRole })
				});
			}

			await fetchUsers();
			cancelEditing();
		} catch (e) {
			console.error('Failed to save:', e);
		} finally {
			saving = false;
		}
	}

	function getRoleBadgeColor(role: string) {
		switch (role) {
			case 'admin':
				return 'bg-red-100 text-red-700';
			case 'reviewer':
				return 'bg-blue-100 text-blue-700';
			case 'banned':
				return 'bg-black text-white';
			default:
				return 'bg-gray-100 text-gray-700';
		}
	}
</script>

<svelte:head>
	<title>{$t.nav.users} - {$t.nav.admin} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-8">
		<h1 class="mb-2 text-4xl font-bold md:text-5xl">{$t.nav.users}</h1>
		<p class="text-lg text-gray-600">{$t.admin.manageUsersAndPermissions}</p>
	</div>

	<!-- Search -->
	<div class="mb-6">
		<div class="relative">
			<Search size={20} class="absolute top-1/2 left-4 -translate-y-1/2 text-gray-400" />
			<input
				type="text"
				placeholder="search by user id, username, email, or slack id..."
				value={searchQuery}
				oninput={handleSearch}
				class="w-full rounded-full border-4 border-black py-3 pr-4 pl-12 focus:border-dashed focus:outline-none"
			/>
		</div>
	</div>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else}
		<div class="overflow-x-auto rounded-2xl border-4 border-black">
			<table class="w-full min-w-[600px]">
				<thead>
					<tr class="border-b-4 border-black bg-black text-white">
						<th class="px-4 py-4 text-left font-bold">user</th>
						{#if user?.role === 'admin' || user?.role === 'creator'}
							<th class="px-4 py-4 text-left font-bold">email</th>
						{/if}
						<th class="px-4 py-4 text-center font-bold">role</th>
						<th class="px-4 py-4 text-center font-bold">scraps</th>
						<th class="px-4 py-4 text-right font-bold">actions</th>
					</tr>
				</thead>
				<tbody>
					{#each users as u (u.id)}
						<tr class="border-b-2 border-black/20 last:border-b-0 hover:bg-gray-50">
							<td class="px-4 py-4">
								<div class="flex items-center gap-3">
									{#if u.avatar}
										<img
											src={u.avatar}
											alt=""
											class="h-10 w-10 rounded-full border-2 border-black object-cover"
										/>
									{:else}
										<div class="h-10 w-10 rounded-full border-2 border-black bg-gray-200"></div>
									{/if}
									<span class="font-bold">{u.username || 'unknown'}</span>
								</div>
							</td>
							{#if user?.role === 'admin' || user?.role === 'creator'}
								<td class="px-4 py-4 text-gray-600">{u.email || '-'}</td>
							{/if}
							<td class="px-4 py-4 text-center">
								<span class="rounded-full px-3 py-1 text-sm font-bold {getRoleBadgeColor(u.role)}">
									{u.role}
								</span>
							</td>
							<td class="px-4 py-4 text-center font-bold">{u.scraps}</td>
							<td class="px-4 py-4 text-right">
								<div class="flex items-center justify-end gap-2">
									<a
										href="/admin/users/{u.id}"
										class="cursor-pointer rounded-full border-4 border-black px-3 py-1 text-sm font-bold transition-all duration-200 hover:border-dashed"
									>
										{$t.admin.view}
									</a>
									<button
										onclick={() => startEditing(u)}
										class="cursor-pointer rounded-full border-4 border-black px-3 py-1 text-sm font-bold transition-all duration-200 hover:border-dashed"
									>
										{$t.common.edit}
									</button>
								</div>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>

		<!-- Pagination -->
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

<!-- Edit Modal -->
{#if editingUser}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && cancelEditing()}
		onkeydown={(e) => e.key === 'Escape' && cancelEditing()}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-lg rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-6 text-2xl font-bold">
				{$t.admin.editUser}: {editingUser.username || 'unknown'}
			</h2>

			<div class="space-y-4">
				{#if user?.role === 'admin' || user?.role === 'creator'}
					<div>
						<label class="mb-1 block text-sm font-bold">role</label>
						<select
							bind:value={editingRole}
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						>
							<option value="member">member</option>
							<option value="reviewer">reviewer</option>
							<option value="admin">admin</option>
							<option value="banned">banned</option>
						</select>
					</div>
				{/if}

				<div>
					<label class="mb-1 block text-sm font-bold">internal notes</label>
					<textarea
						bind:value={editingNotes}
						rows="4"
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
				</div>
			</div>

			<div class="mt-6 flex gap-3">
				<button
					onclick={cancelEditing}
					disabled={saving}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={saveChanges}
					disabled={saving}
					class="flex-1 cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
				>
					{saving ? $t.common.saving : $t.common.save}
				</button>
			</div>
		</div>
	</div>
{/if}
