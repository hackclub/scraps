<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		ArrowLeft,
		Package,
		Clock,
		CheckCircle,
		XCircle,
		AlertTriangle,
		Plus,
		Gift,
		Spool,
		Lock,
		Unlock,
		History,
		TrendingUp,
		TrendingDown,
		Undo2,
		ShoppingCart,
		Dices,
		FileText,
		ShieldAlert
	} from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { formatHours } from '$lib/utils';
	import { t } from '$lib/i18n';

	let { data } = $props();

	interface Project {
		id: number;
		name: string;
		status: string;
		hours: number;
		hoursOverride: number | null;
		createdAt: string;
		updatedAt: string;
		deleted: number | null;
	}

	interface UserStats {
		total: number;
		shipped: number;
		inProgress: number;
		waitingForReview: number;
		rejected: number;
		totalHours: number;
	}

	interface TargetUser {
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

	interface CurrentUser {
		id: number;
		role: string;
	}

	interface Bonus {
		id: number;
		amount: number;
		reason: string;
		givenBy: number | null;
		givenByUsername: string | null;
		createdAt: string;
	}

	let currentUser = $state<CurrentUser | null>(null);
	let targetUser = $state<TargetUser | null>(null);
	let projects = $state<Project[]>([]);
	let stats = $state<UserStats | null>(null);
	let bonuses = $state<Bonus[]>([]);
	let hackatimeSuspected = $state(false);
	let hackatimeBanned = $state(false);
	let loading = $state(true);
	let saving = $state(false);
	let editingNotes = $state('');
	let editingRole = $state('');

	let showBonusModal = $state(false);
	let bonusAmount = $state<number | null>(null);
	let bonusReason = $state('');
	let savingBonus = $state(false);
	let bonusError = $state<string | null>(null);

	interface TimelineEvent {
		type: string;
		amount: number;
		description: string;
		date: string;
		locked?: boolean;
		itemName?: string;
		paid?: boolean;
		orderId?: number;
	}

	let timeline = $state<TimelineEvent[]>([]);
	let timelineBalance = $state<{
		earned: number;
		pending: number;
		spent: number;
		balance: number;
	} | null>(null);
	let timelineLoading = $state(false);
	let showTimeline = $state(false);
	let undoingOrder = $state<number | null>(null);
	let showUndoConfirm = $state<number | null>(null);
	let showUnshipConfirm = $state<number | null>(null);
	let unshipReason = $state('');
	let unshipping = $state(false);

	// lightweight toast helper (DOM-based, so no extra markup required)
	function showToast(message: string, type: 'success' | 'error' | 'info' = 'info') {
		try {
			const el = document.createElement('div');
			el.textContent = message;
			el.style.position = 'fixed';
			el.style.left = '50%';
			el.style.bottom = '24px';
			el.style.transform = 'translateX(-50%)';
			el.style.padding = '8px 14px';
			el.style.borderRadius = '999px';
			el.style.fontWeight = '700';
			el.style.zIndex = '9999';
			el.style.boxShadow = '0 6px 18px rgba(0,0,0,0.25)';
			el.style.opacity = '1';
			el.style.transition = 'opacity 250ms ease';
			if (type === 'success') {
				el.style.background = '#16a34a'; // green-600
				el.style.color = 'white';
			} else if (type === 'error') {
				el.style.background = '#dc2626'; // red-600
				el.style.color = 'white';
			} else {
				el.style.background = '#111827';
				el.style.color = 'white';
			}
			document.body.appendChild(el);
			window.setTimeout(() => {
				el.style.opacity = '0';
				window.setTimeout(() => {
					el.remove();
				}, 300);
			}, 3500);
		} catch (err) {
			// Fallback to alert if the DOM approach fails
			try {
				alert(message);
			} catch {}
		}
	}

	onMount(async () => {
		currentUser = await getUser();
		if (!currentUser || (currentUser.role !== 'admin' && currentUser.role !== 'reviewer')) {
			goto('/dashboard');
			return;
		}

		try {
			const [userResponse, bonusesResponse] = await Promise.all([
				fetch(`${API_URL}/admin/users/${data.id}`, { credentials: 'include' }),
				currentUser.role === 'admin'
					? fetch(`${API_URL}/admin/users/${data.id}/bonuses`, { credentials: 'include' })
					: Promise.resolve(null)
			]);

			if (userResponse.ok) {
				const result = await userResponse.json();
				targetUser = result.user;
				projects = result.projects || [];
				stats = result.stats;
				hackatimeSuspected = result.hackatimeSuspected || false;
				hackatimeBanned = result.hackatimeBanned || false;
				editingNotes = result.user?.internalNotes || '';
				editingRole = result.user?.role || 'member';
			}

			if (bonusesResponse?.ok) {
				bonuses = await bonusesResponse.json();
			}
		} catch (e) {
			console.error('Failed to fetch user:', e);
		} finally {
			loading = false;
		}
	});

	async function saveChanges() {
		if (!targetUser) return;
		saving = true;

		try {
			await fetch(`${API_URL}/admin/users/${targetUser.id}/notes`, {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ internalNotes: editingNotes })
			});

			if (currentUser?.role === 'admin' && editingRole !== targetUser.role) {
				await fetch(`${API_URL}/admin/users/${targetUser.id}/role`, {
					method: 'PUT',
					headers: { 'Content-Type': 'application/json' },
					credentials: 'include',
					body: JSON.stringify({ role: editingRole })
				});
				targetUser.role = editingRole;
			}

			targetUser.internalNotes = editingNotes;
		} catch (e) {
			console.error('Failed to save:', e);
		} finally {
			saving = false;
		}
	}

	async function saveBonus() {
		if (!targetUser || !bonusAmount || !bonusReason.trim()) return;
		savingBonus = true;
		bonusError = null;

		try {
			const response = await fetch(`${API_URL}/admin/users/${targetUser.id}/bonus`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ amount: bonusAmount, reason: bonusReason.trim() })
			});

			const result = await response.json();

			if (!response.ok) {
				throw new Error(result.error || 'Failed to save bonus');
			}

			bonuses = [
				{
					...result,
					givenByUsername: currentUser?.id === result.givenBy ? 'you' : null
				},
				...bonuses
			];
			targetUser.scraps += bonusAmount;
			showBonusModal = false;
			bonusAmount = null;
			bonusReason = '';
		} catch (e) {
			bonusError = e instanceof Error ? e.message : 'Failed to save bonus';
		} finally {
			savingBonus = false;
		}
	}

	async function fetchTimeline() {
		if (!targetUser) return;
		timelineLoading = true;
		try {
			const res = await fetch(`${API_URL}/admin/users/${targetUser.id}/timeline`, {
				credentials: 'include'
			});
			if (res.ok) {
				const result = await res.json();
				timeline = result.timeline;
				timelineBalance = result.balance;
			}
		} catch (e) {
			console.error('Failed to fetch timeline:', e);
		} finally {
			timelineLoading = false;
		}
	}

	async function undoOrder(orderId: number) {
		undoingOrder = orderId;
		showUndoConfirm = null;
		try {
			// Directly call DELETE with a required reason payload.
			// The server expects a short reason when deleting/reverting an order.
			const refundRes = await fetch(`${API_URL}/admin/orders/${orderId}`, {
				method: 'DELETE',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ reason: 'reverted via admin UI' })
			});
			const refundResult = await refundRes.json();
			if (refundResult.error) {
				console.error(refundResult.error);
				return;
			}
			await fetchTimeline();
		} catch (e) {
			console.error('Failed to undo order:', e);
		} finally {
			undoingOrder = null;
		}
	}

	async function unshipProject(projectId: number) {
		unshipping = true;
		try {
			const res = await fetch(`${API_URL}/admin/projects/${projectId}/unship`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ reason: unshipReason.trim() || undefined })
			});
			const result = await res.json();
			if (result.error) {
				console.error(result.error);
				return;
			}
			// Update local project status
			projects = projects.map((p) => (p.id === projectId ? { ...p, status: 'in_progress' } : p));
			showUnshipConfirm = null;
			unshipReason = '';
		} catch (e) {
			console.error('Failed to unship project:', e);
		} finally {
			unshipping = false;
		}
	}

	function getTimelineIcon(type: string) {
		switch (type) {
			case 'earned':
				return TrendingUp;
			case 'bonus':
				return Gift;
			case 'shop_purchase':
				return ShoppingCart;
			case 'shop_luck_win':
				return Dices;
			case 'shop_consolation':
				return FileText;
			case 'refinery_upgrade':
				return Spool;
			case 'refinery_consumed':
				return TrendingDown;
			default:
				return Clock;
		}
	}

	function getTimelineColor(type: string, amount: number) {
		if (type === 'refinery_consumed') return 'text-orange-600';
		if (amount > 0) return 'text-green-600';
		if (amount < 0) return 'text-red-600';
		return 'text-gray-600';
	}

	function getTimelineLabel(type: string) {
		switch (type) {
			case 'earned':
				return 'scraps earned';
			case 'bonus':
				return 'bonus';
			case 'shop_purchase':
				return 'shop purchase';
			case 'shop_luck_win':
				return 'lucky win';
			case 'shop_consolation':
				return 'consolation roll';
			case 'refinery_upgrade':
				return 'refinery upgrade';
			case 'refinery_consumed':
				return 'consumed by win';
			default:
				return type;
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

	function getStatusIcon(status: string) {
		switch (status) {
			case 'shipped':
				return CheckCircle;
			case 'waiting_for_review':
				return Clock;
			case 'in_progress':
				return AlertTriangle;
			case 'permanently_rejected':
				return XCircle;
			default:
				return Package;
		}
	}

	function getStatusColor(status: string) {
		switch (status) {
			case 'shipped':
				return 'text-green-600';
			case 'waiting_for_review':
			case 'in_progress':
				return 'text-yellow-600';
			case 'permanently_rejected':
				return 'text-red-600';
			default:
				return 'text-gray-600';
		}
	}

	function getStatusTag(status: string) {
		switch (status) {
			case 'shipped':
				return {
					label: 'approved',
					bg: 'bg-green-100',
					text: 'text-green-700',
					border: 'border-green-600'
				};
			case 'in_progress':
			case 'waiting_for_review':
				return {
					label: 'in progress',
					bg: 'bg-yellow-100',
					text: 'text-yellow-700',
					border: 'border-yellow-600'
				};
			case 'permanently_rejected':
				return {
					label: 'permanently rejected',
					bg: 'bg-red-100',
					text: 'text-red-700',
					border: 'border-red-600'
				};
			default:
				return {
					label: status.replace(/_/g, ' '),
					bg: 'bg-gray-100',
					text: 'text-gray-700',
					border: 'border-gray-600'
				};
		}
	}
</script>

<svelte:head>
	<title>{targetUser?.username || 'user'} - admin - scraps</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<a
		href="/admin/users"
		class="mb-8 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
	>
		<ArrowLeft size={20} />
		{$t.project.back}
	</a>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if !targetUser}
		<div class="py-12 text-center text-gray-500">{$t.profile.userNotFound}</div>
	{:else}
		<!-- User Header -->
		<div class="mb-6 rounded-2xl border-4 border-black p-6">
			<div class="flex items-start gap-6">
				{#if targetUser.avatar}
					<img
						src={targetUser.avatar}
						alt=""
						class="h-20 w-20 rounded-full border-4 border-black"
					/>
				{:else}
					<div class="h-20 w-20 rounded-full border-4 border-black bg-gray-200"></div>
				{/if}
				<div class="flex-1">
					<div class="mb-2 flex items-center gap-3">
						<h1 class="text-3xl font-bold">{targetUser.username || 'unknown'}</h1>
						<span
							class="rounded-full px-3 py-1 text-sm font-bold {getRoleBadgeColor(targetUser.role)}"
						>
							{targetUser.role}
						</span>
					</div>
					{#if targetUser.email}
						<p class="mb-2 text-gray-600">{targetUser.email}</p>
					{/if}
					<div class="flex items-center gap-4 text-sm text-gray-500">
						<span>joined {new Date(targetUser.createdAt).toLocaleDateString()}</span>
						{#if targetUser.slackId}
							<span>slack: {targetUser.slackId}</span>
						{/if}
					</div>
				</div>
				<div class="text-right">
					<div class="flex items-center justify-end gap-2">
						<Spool size={28} />
						<p class="text-4xl font-bold">{targetUser.scraps}</p>
					</div>
					<p class="text-sm text-gray-500">{$t.common.scraps}</p>
					{#if currentUser?.role === 'admin'}
						<button
							onclick={() => (showBonusModal = true)}
							class="mt-2 flex cursor-pointer items-center gap-1 rounded-full bg-green-500 px-3 py-1 text-sm font-bold text-white transition-all hover:bg-green-600"
						>
							<Plus size={14} />
							give bonus
						</button>
					{/if}
				</div>
			</div>
		</div>

		<!-- Hackatime Status Banners (admin-only) -->
		{#if hackatimeBanned}
			<div class="mb-6 rounded-2xl border-4 border-red-600 bg-red-50 p-4">
				<div class="flex items-center gap-3">
					<ShieldAlert size={20} class="text-red-600" />
					<div>
						<p class="font-bold text-red-800">hackatime banned</p>
						<p class="text-sm text-red-700">
							this user is banned on hackatime. they will be redirected to fraud.land on login.
						</p>
					</div>
				</div>
			</div>
		{/if}
		{#if hackatimeSuspected}
			<div class="mb-6 rounded-2xl border-4 border-orange-500 bg-orange-50 p-4">
				<div class="flex items-center gap-3">
					<ShieldAlert size={20} class="text-orange-600" />
					<div>
						<p class="font-bold text-orange-800">hackatime suspected</p>
						<p class="text-sm text-orange-700">
							this user is flagged as suspected on hackatime. please review their activity
							carefully.
						</p>
					</div>
				</div>
			</div>
		{/if}

		<!-- Stats -->
		{#if stats}
			<div class="mb-6 grid grid-cols-2 gap-4 md:grid-cols-4">
				<div class="rounded-2xl border-4 border-black p-4 text-center">
					<p class="text-3xl font-bold">{stats.total}</p>
					<p class="text-sm text-gray-500">total projects</p>
				</div>
				<div class="rounded-2xl border-4 border-black p-4 text-center">
					<p class="text-3xl font-bold text-green-600">{stats.shipped}</p>
					<p class="text-sm text-gray-500">shipped</p>
				</div>
				<div class="rounded-2xl border-4 border-black p-4 text-center">
					<p class="text-3xl font-bold text-yellow-600">{stats.waitingForReview}</p>
					<p class="text-sm text-gray-500">pending review</p>
				</div>
				<div class="rounded-2xl border-4 border-black p-4 text-center">
					<p class="text-3xl font-bold">{formatHours(stats.totalHours)}h</p>
					<p class="text-sm text-gray-500">total hours</p>
				</div>
			</div>
		{/if}

		<!-- Internal Notes & Role -->
		<div class="mb-6 rounded-2xl border-4 border-black bg-yellow-50 p-6">
			<h2 class="mb-4 text-xl font-bold">admin settings</h2>
			<div class="space-y-4">
				{#if currentUser?.role === 'admin'}
					<div>
						<label for="role" class="mb-1 block text-sm font-bold">role</label>
						<select
							id="role"
							bind:value={editingRole}
							class="w-full rounded-lg border-2 border-black bg-white px-4 py-2 focus:border-dashed focus:outline-none"
						>
							<option value="member">member</option>
							<option value="reviewer">reviewer</option>
							<option value="admin">admin</option>
							<option value="banned">banned</option>
						</select>
						{#if editingRole === 'banned'}
							<p class="mt-1 flex items-center gap-1 text-xs text-red-600">
								<AlertTriangle size={12} />
								banning will redirect this user to fraud.land on login
							</p>
						{/if}
					</div>
				{/if}

				<div>
					<label for="notes" class="mb-1 block text-sm font-bold">internal notes</label>
					<textarea
						id="notes"
						bind:value={editingNotes}
						rows="4"
						placeholder="Notes about this user (visible to reviewers only)"
						class="w-full resize-none rounded-lg border-2 border-black bg-white px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
				</div>

				<button
					onclick={saveChanges}
					disabled={saving}
					class="cursor-pointer rounded-full bg-black px-6 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
				>
					{saving ? $t.common.saving : $t.project.saveChanges}
				</button>
			</div>
		</div>

		<!-- Projects -->
		<div class="rounded-2xl border-4 border-black p-6">
			<h2 class="mb-4 text-xl font-bold">{$t.profile.projects} ({projects.length})</h2>
			{#if projects.length === 0}
				<p class="text-gray-500">{$t.profile.noProjectsFound}</p>
			{:else}
				<div class="space-y-3">
					{#each projects as project}
						{@const StatusIcon = getStatusIcon(project.status)}
						{@const statusTag = getStatusTag(project.status)}
						<a
							href="/admin/reviews/{project.id}"
							class="flex cursor-pointer items-center justify-between rounded-lg border-2 border-black p-4 transition-all duration-200 hover:border-dashed {project.deleted
								? 'opacity-50'
								: ''}"
						>
							<div class="flex items-center gap-3">
								<StatusIcon size={20} class={getStatusColor(project.status)} />
								<div>
									<p class="font-bold">
										{project.name}
										{#if project.deleted}
											<span class="ml-2 text-xs font-normal text-red-500">(deleted)</span>
										{/if}
									</p>
									<p class="text-xs text-gray-500">
										{formatHours(project.hoursOverride ?? project.hours)}h
									</p>
								</div>
							</div>
							<div class="flex items-center gap-3">
								{#if project.deleted}
									<span
										class="rounded-full border border-red-500 bg-red-100 px-2 py-1 text-xs font-bold text-red-700"
									>
										deleted
									</span>
								{:else}
									<span
										class="rounded-full border px-2 py-1 text-xs font-bold {statusTag.bg} {statusTag.text} {statusTag.border}"
									>
										{statusTag.label}
									</span>
								{/if}
								{#if project.status === 'shipped' && currentUser?.role === 'admin'}
									<button
										onclick={(e) => {
											e.preventDefault();
											e.stopPropagation();
											showUnshipConfirm = project.id;
										}}
										class="cursor-pointer rounded-full border-2 border-red-600 px-2 py-1 text-xs font-bold text-red-600 transition-all duration-200 hover:border-dashed"
									>
										unship
									</button>
								{/if}
								<span class="text-xs text-gray-500">
									{new Date(project.updatedAt).toLocaleDateString()}
								</span>
							</div>
						</a>
					{/each}
				</div>
			{/if}
		</div>

		<!-- Bonuses (admin only) -->
		{#if currentUser?.role === 'admin'}
			<div class="mt-6 rounded-2xl border-4 border-black bg-green-50 p-6">
				<div class="mb-4 flex items-center justify-between">
					<h2 class="flex items-center gap-2 text-xl font-bold">
						<Gift size={20} />
						bonus history ({bonuses.length})
					</h2>
				</div>
				{#if bonuses.length === 0}
					<p class="text-gray-500">no bonuses given yet</p>
				{:else}
					<div class="space-y-3">
						{#each bonuses as bonus}
							<div class="rounded-lg border-2 border-black bg-white p-3">
								<div class="flex items-start justify-between">
									<div class="flex-1">
										<p
											class="text-lg font-bold {bonus.amount >= 0
												? 'text-green-600'
												: 'text-red-600'}"
										>
											{bonus.amount >= 0 ? '+' : ''}{bonus.amount} scraps
										</p>
										<p class="text-sm text-gray-700">{bonus.reason}</p>
									</div>
									<div class="text-right text-xs text-gray-500">
										<p>{new Date(bonus.createdAt).toLocaleDateString()}</p>
										<p>by @{bonus.givenByUsername || 'unknown'}</p>
									</div>
								</div>
							</div>
						{/each}
					</div>
				{/if}
			</div>

			<!-- Financial Timeline -->
			<div class="mt-6 rounded-2xl border-4 border-black p-6">
				<div class="mb-4 flex items-center justify-between">
					<h2 class="flex items-center gap-2 text-xl font-bold">
						<History size={20} />
						financial timeline
					</h2>
					{#if !showTimeline}
						<button
							onclick={() => {
								showTimeline = true;
								fetchTimeline();
							}}
							class="cursor-pointer rounded-full border-4 border-black px-4 py-2 text-sm font-bold transition-all duration-200 hover:border-dashed"
						>
							load timeline
						</button>
					{/if}
				</div>

				{#if !showTimeline}
					<p class="text-gray-500">click "load timeline" to view the full financial history</p>
				{:else if timelineLoading}
					<div class="py-8 text-center text-gray-500">{$t.common.loading}</div>
				{:else}
					{#if timelineBalance}
						<div class="mb-6 grid grid-cols-2 gap-3 md:grid-cols-4">
							<div class="rounded-lg border-2 border-black p-3 text-center">
								<p class="text-xl font-bold text-green-600">{timelineBalance.earned}</p>
								<p class="text-xs text-gray-500">earned</p>
							</div>
							<div class="rounded-lg border-2 border-black p-3 text-center">
								<p class="text-xl font-bold text-yellow-600">{timelineBalance.pending}</p>
								<p class="text-xs text-gray-500">pending</p>
							</div>
							<div class="rounded-lg border-2 border-black p-3 text-center">
								<p class="text-xl font-bold text-red-600">{timelineBalance.spent}</p>
								<p class="text-xs text-gray-500">spent</p>
							</div>
							<div class="rounded-lg border-2 border-black p-3 text-center">
								<p class="text-xl font-bold">{timelineBalance.balance}</p>
								<p class="text-xs text-gray-500">balance</p>
							</div>
						</div>
					{/if}

					{#if timeline.length === 0}
						<p class="text-gray-500">no financial activity yet</p>
					{:else}
						<div class="space-y-2">
							{#each timeline as event}
								{@const Icon = getTimelineIcon(event.type)}
								<div class="flex items-center gap-3 rounded-lg border-2 border-black p-3">
									<div
										class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full {event.amount >
										0
											? 'bg-green-100'
											: event.amount < 0
												? 'bg-red-100'
												: 'bg-gray-100'}"
									>
										<Icon size={16} class={getTimelineColor(event.type, event.amount)} />
									</div>
									<div class="min-w-0 flex-1">
										<div class="flex flex-wrap items-center gap-2">
											<span
												class="text-xs font-bold uppercase {getTimelineColor(
													event.type,
													event.amount
												)}"
											>
												{getTimelineLabel(event.type)}
											</span>
											{#if event.type === 'refinery_upgrade'}
												{#if event.locked}
													<span
														class="flex items-center gap-1 rounded-full bg-red-100 px-2 py-0.5 text-xs font-bold text-red-700"
													>
														<Lock size={10} />
														locked
													</span>
												{:else}
													<span
														class="flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-xs font-bold text-green-700"
													>
														<Unlock size={10} />
														undoable
													</span>
												{/if}
											{/if}
											{#if event.type === 'refinery_consumed'}
												<span
													class="rounded-full bg-orange-100 px-2 py-0.5 text-xs font-bold text-orange-700"
												>
													consumed
												</span>
											{/if}
											{#if event.type === 'earned' && !event.paid}
												<span
													class="rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-bold text-yellow-700"
												>
													unpaid
												</span>
											{/if}
										</div>
										<p class="truncate text-sm text-gray-700">{event.description}</p>
									</div>
									<div class="flex shrink-0 items-center gap-2">
										{#if event.type.startsWith('shop_') && event.orderId}
											{#if showUndoConfirm === event.orderId}
												<div class="flex items-center gap-1">
													<button
														onclick={() => undoOrder(event.orderId ?? 0)}
														disabled={undoingOrder === event.orderId}
														class="cursor-pointer rounded-full bg-red-600 px-2 py-1 text-xs font-bold text-white transition-all duration-200 hover:bg-red-700 disabled:opacity-50"
													>
														{undoingOrder === event.orderId ? '...' : 'confirm'}
													</button>
													<button
														onclick={() => (showUndoConfirm = null)}
														class="cursor-pointer rounded-full border-2 border-black px-2 py-1 text-xs font-bold transition-all duration-200 hover:border-dashed"
													>
														cancel
													</button>
												</div>
											{:else}
												<button
													onclick={() => (showUndoConfirm = event.orderId ?? null)}
													class="cursor-pointer rounded-full border-2 border-red-600 px-2 py-1 text-xs font-bold text-red-600 transition-all duration-200 hover:border-dashed disabled:opacity-50"
												>
													<Undo2 size={12} />
												</button>
											{/if}
										{/if}
										<div class="text-right">
											<p class="font-bold {getTimelineColor(event.type, event.amount)}">
												{#if event.amount !== 0}
													{event.amount > 0 ? '+' : ''}{event.amount}
												{/if}
											</p>
											<p class="text-xs text-gray-500">
												{new Date(event.date).toLocaleDateString()}
												{new Date(event.date).toLocaleTimeString([], {
													hour: '2-digit',
													minute: '2-digit'
												})}
											</p>
										</div>
									</div>
								</div>
							{/each}
						</div>
					{/if}
				{/if}
			</div>
		{/if}
	{/if}
</div>

<!-- Bonus Modal -->
{#if showUnshipConfirm !== null}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (showUnshipConfirm = null)}
		onkeydown={(e) => e.key === 'Escape' && (showUnshipConfirm = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">unship project</h2>
			<p class="mb-4 text-gray-600">
				this will set the project back to in progress and remove all awarded scraps. this action
				cannot be undone.
			</p>
			<div class="mb-4">
				<label for="unshipReason" class="mb-1 block text-sm font-bold">reason (optional)</label>
				<textarea
					id="unshipReason"
					bind:value={unshipReason}
					rows="3"
					placeholder="why are you unshipping this project?"
					class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
				></textarea>
			</div>
			<div class="flex gap-3">
				<button
					onclick={() => {
						showUnshipConfirm = null;
						unshipReason = '';
					}}
					disabled={unshipping}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
				>
					cancel
				</button>
				<button
					onclick={() => showUnshipConfirm !== null && unshipProject(showUnshipConfirm)}
					disabled={unshipping}
					class="flex-1 cursor-pointer rounded-full border-4 border-black bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
				>
					{unshipping ? 'unshipping...' : 'unship project'}
				</button>
			</div>
		</div>
	</div>
{/if}

{#if showBonusModal}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (showBonusModal = false)}
		onkeydown={(e) => e.key === 'Escape' && (showBonusModal = false)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">give bonus scraps</h2>

			{#if bonusError}
				<div class="mb-4 rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
					{bonusError}
				</div>
			{/if}

			<div class="space-y-4">
				<div>
					<label for="bonusAmount" class="mb-1 block text-sm font-bold"
						>amount <span class="text-red-500">*</span></label
					>
					<input
						id="bonusAmount"
						type="number"
						bind:value={bonusAmount}
						placeholder="e.g. 100 or -50"
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
					<p class="mt-1 text-xs text-gray-500">use negative numbers to deduct scraps</p>
				</div>

				<div>
					<label for="bonusReason" class="mb-1 block text-sm font-bold"
						>reason <span class="text-red-500">*</span></label
					>
					<textarea
						id="bonusReason"
						bind:value={bonusReason}
						rows="3"
						placeholder="why are you giving this bonus?"
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
				</div>
			</div>

			<div class="mt-6 flex gap-3">
				<button
					onclick={() => (showBonusModal = false)}
					disabled={savingBonus}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={saveBonus}
					disabled={savingBonus || !bonusAmount || !bonusReason.trim()}
					class="flex-1 cursor-pointer rounded-full bg-green-500 px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-green-600 disabled:cursor-not-allowed disabled:opacity-50"
				>
					{savingBonus ? $t.common.saving : 'give bonus'}
				</button>
			</div>
		</div>
	</div>
{/if}
