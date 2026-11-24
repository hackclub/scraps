<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		ArrowLeft,
		Clock,
		AlertTriangle,
		Gift,
		Spool,
		Lock,
		Unlock,
		History,
		TrendingUp,
		TrendingDown,
		Trash2,
		ShoppingCart,
		Dices,
		FileText,
		ShieldAlert,
		Monitor,
		MessageCircle,
		XCircle,
		Scale
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
		scrapsAwarded: number;
		scrapsPaidAmount: number;
		scrapsPaidAt: string | null;
		createdAt: string;
		updatedAt: string;
		deleted: number | null;
		payoutRoll: {
			status: string;
			baseScraps: number;
			roll1: number | null;
			roll2: number | null;
			finalMultiplier: number | null;
			delta: number | null;
		} | null;
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

	interface RetainedShop {
		cap: number;
		used: number;
		items: { id: number; name: string; image: string | null; count: number }[];
	}

	interface Order {
		id: number;
		isFulfilled: boolean;
		itemName: string | null;
		itemImage: string | null;
		quantity: number;
		totalPrice: number;
		status: string;
		orderType: string;
		size: string | null;
		createdAt: string;
	}

	let orders = $state<Order[]>([]);
	let pendingOrders = $derived(
		orders.filter((o) => !o.isFulfilled && o.status !== 'cancelled' && o.status !== 'deleted')
	);
	let orderSort = $state<'newest' | 'oldest' | 'price_desc' | 'price_asc' | 'status' | 'type'>(
		'newest'
	);
	let orderFilter = $state<'pending' | 'all' | 'fulfilled' | 'cancelled'>('pending');
	let sortedOrders = $derived.by(() => {
		const list = orders.filter((o) => {
			const cancelled = o.status === 'cancelled' || o.status === 'deleted';
			if (orderFilter === 'pending') return !o.isFulfilled && !cancelled;
			if (orderFilter === 'fulfilled') return o.isFulfilled;
			if (orderFilter === 'cancelled') return cancelled;
			return true;
		});
		const time = (o: Order) => new Date(o.createdAt).getTime();
		const rank = (o: Order) =>
			o.isFulfilled ? 2 : o.status === 'cancelled' || o.status === 'deleted' ? 3 : 0;
		switch (orderSort) {
			case 'oldest':
				return list.sort((a, b) => time(a) - time(b));
			case 'price_desc':
				return list.sort((a, b) => b.totalPrice - a.totalPrice);
			case 'price_asc':
				return list.sort((a, b) => a.totalPrice - b.totalPrice);
			case 'status':
				return list.sort((a, b) => rank(a) - rank(b) || time(b) - time(a));
			case 'type':
				return list.sort((a, b) => a.orderType.localeCompare(b.orderType) || time(b) - time(a));
			default:
				return list.sort((a, b) => time(b) - time(a));
		}
	});

	function orderStatusLabel(o: Order) {
		if (o.isFulfilled) return 'fulfilled';
		return o.status;
	}

	function orderStatusClass(o: Order) {
		if (o.isFulfilled) return 'bg-green-100 text-green-700';
		if (o.status === 'cancelled' || o.status === 'deleted') return 'bg-gray-200 text-gray-600';
		if (o.status === 'unclaimed') return 'bg-blue-100 text-blue-700';
		return 'bg-yellow-100 text-yellow-800';
	}
	let currentUser = $state<CurrentUser | null>(null);
	let targetUser = $state<TargetUser | null>(null);
	let projects = $state<Project[]>([]);
	let stats = $state<UserStats | null>(null);
	let retainedShop = $state<RetainedShop | null>(null);
	let hackatimeSuspected = $state(false);
	let hackatimeBanned = $state(false);
	let hackatimeUserId = $state<number | null>(null);

	let actionModal = $state<'reject' | 'adjust' | null>(null);
	let actionAmount = $state<number | null>(null);
	let actionInternalReason = $state('');
	let actionUserReason = $state('');
	let actionSaving = $state(false);
	let actionError = $state<string | null>(null);
	let actionRefund = $state(true);
	let loading = $state(true);
	let saving = $state(false);
	let editingNotes = $state('');
	let editingRole = $state('');

	interface TimelineEvent {
		type: string;
		amount: number;
		description: string;
		date: string;
		locked?: boolean;
		itemName?: string;
		paid?: boolean;
		orderId?: number;
		bonusId?: number;
	}

	let timeline = $state<TimelineEvent[]>([]);
	let timelineBalance = $state<{
		earned: number;
		pending: number;
		spent: number;
		balance: number;
	} | null>(null);
	let timelineLoading = $state(false);
	let undoingOrder = $state<number | null>(null);
	let deletingBonus = $state<number | null>(null);
	let showDeleteConfirm = $state<
		{ type: 'order'; id: number } | { type: 'bonus'; id: number } | null
	>(null);
	let showUnshipConfirm = $state<number | null>(null);
	let unshipReason = $state('');
	let unshipping = $state(false);

	let showDeleteUserConfirm = $state(false);
	let deletingUser = $state(false);

	// lightweight toast helper (DOM-based, so no extra markup required)
	function _showToast(message: string, type: 'success' | 'error' | 'info' = 'info') {
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
		} catch (_err) {
			// Fallback to alert if the DOM approach fails
			try {
				alert(message);
			} catch {}
		}
	}

	onMount(async () => {
		currentUser = await getUser();
		if (
			!currentUser ||
			(currentUser.role !== 'admin' &&
				currentUser.role !== 'reviewer' &&
				currentUser.role !== 'creator')
		) {
			goto('/dashboard');
			return;
		}

		if (currentUser.role === 'admin' || currentUser.role === 'creator') fetchTimeline();

		try {
			const userResponse = await fetch(`${API_URL}/admin/users/${data.id}`, {
				credentials: 'include'
			});

			if (userResponse.ok) {
				const result = await userResponse.json();
				targetUser = result.user;
				projects = result.projects || [];
				stats = result.stats;
				retainedShop = result.retainedShop || null;
				orders = result.orders || [];
				hackatimeSuspected = result.hackatimeSuspected || false;
				hackatimeBanned = result.hackatimeBanned || false;
				hackatimeUserId = result.hackatimeUserId ?? null;
				editingNotes = result.user?.internalNotes || '';
				editingRole = result.user?.role || 'member';
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

			if (
				(currentUser?.role === 'admin' || currentUser?.role === 'creator') &&
				editingRole !== targetUser.role
			) {
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

	function openActionModal(kind: 'reject' | 'adjust') {
		actionModal = kind;
		actionAmount = null;
		actionInternalReason = '';
		actionUserReason = '';
		actionError = null;
		actionRefund = true;
	}

	async function submitAction() {
		if (!targetUser || !actionModal) return;
		actionSaving = true;
		actionError = null;
		const kind = actionModal;
		try {
			const path = kind === 'reject' ? 'reject-all-orders' : 'adjust-balance';
			const body: Record<string, unknown> = {
				internalReason: actionInternalReason.trim(),
				userReason: actionUserReason.trim()
			};
			if (kind === 'adjust') body.amount = actionAmount;
			if (kind === 'reject') body.refund = actionRefund;
			const res = await fetch(`${API_URL}/admin/users/${targetUser.id}/${path}`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify(body)
			});
			const result = await res.json();
			if (!res.ok || result.error) throw new Error(result.error || 'Request failed');

			const dmNote = result.dmSent ? 'DM sent' : 'DM NOT sent';
			if (kind === 'reject') {
				const rejectedIds = new Set((result.rejected || []).map((r: { id: number }) => r.id));
				orders = orders.map((o) => (rejectedIds.has(o.id) ? { ...o, status: 'cancelled' } : o));
				targetUser.scraps += result.totalRefund || 0;
				const skipped = (result.skipped || []).length;
				_showToast(
					`rejected ${rejectedIds.size} order(s), refunded ${result.totalRefund}${result.withheld ? `, withheld ${result.withheld}` : ''}${skipped ? `, skipped ${skipped}` : ''} · ${dmNote}`,
					skipped ? 'error' : result.dmSent ? 'success' : 'info'
				);
			} else {
				targetUser.scraps = result.newBalance;
				_showToast(
					`balance changed by ${result.amount} · ${dmNote}`,
					result.dmSent ? 'success' : 'info'
				);
			}
			actionModal = null;
			await fetchTimeline();
		} catch (e) {
			actionError = e instanceof Error ? e.message : 'Request failed';
		} finally {
			actionSaving = false;
		}
	}

	async function fetchTimeline() {
		timelineLoading = true;
		try {
			const res = await fetch(`${API_URL}/admin/users/${data.id}/timeline`, {
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
		showDeleteConfirm = null;
		try {
			const refundRes = await fetch(`${API_URL}/admin/orders/${orderId}`, {
				method: 'DELETE',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ reason: 'reverted via admin timeline' })
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

	async function deleteBonus(bonusId: number) {
		deletingBonus = bonusId;
		showDeleteConfirm = null;
		try {
			const res = await fetch(`${API_URL}/admin/bonuses/${bonusId}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			const result = await res.json();
			if (result.error) {
				console.error(result.error);
				return;
			}
			await fetchTimeline();
		} catch (e) {
			console.error('Failed to delete bonus:', e);
		} finally {
			deletingBonus = null;
		}
	}

	function confirmTimelineDelete(event: TimelineEvent) {
		if (event.type === 'bonus' && event.bonusId) {
			showDeleteConfirm = { type: 'bonus', id: event.bonusId };
		} else if (event.type.startsWith('shop_') && event.orderId) {
			showDeleteConfirm = { type: 'order', id: event.orderId };
		}
	}

	function executeTimelineDelete() {
		if (!showDeleteConfirm) return;
		if (showDeleteConfirm.type === 'bonus') {
			deleteBonus(showDeleteConfirm.id);
		} else {
			undoOrder(showDeleteConfirm.id);
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

	async function deleteUser() {
		if (!targetUser) return;
		deletingUser = true;
		try {
			const res = await fetch(`${API_URL}/admin/users/${targetUser.id}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			const result = await res.json();
			if (!res.ok) {
				_showToast(result.error || 'Failed to delete user', 'error');
				return;
			}
			_showToast('User deleted successfully', 'success');
			goto('/admin/users');
		} catch (e) {
			console.error('Failed to delete user:', e);
			_showToast('Failed to delete user', 'error');
		} finally {
			deletingUser = false;
			showDeleteUserConfirm = false;
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
			case 'creator':
				return 'bg-purple-100 text-purple-700';
			case 'reviewer':
				return 'bg-blue-100 text-blue-700';
			case 'banned':
				return 'bg-black text-white';
			default:
				return 'bg-gray-100 text-gray-700';
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

<div class="mx-auto max-w-7xl px-4 pt-24 pb-24 md:px-8">
	<a
		href="/admin/users"
		class="mb-4 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
	>
		<ArrowLeft size={20} />
		{$t.project.back}
	</a>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if !targetUser}
		<div class="py-12 text-center text-gray-500">{$t.profile.userNotFound}</div>
	{:else}
		<div class="grid gap-6 lg:grid-cols-[22rem_minmax(0,1fr)] lg:items-start">
			<aside class="space-y-4">
				<div class="rounded-2xl border-4 border-black p-4">
					<div class="flex items-center gap-3">
						{#if targetUser.avatar}
							<img
								src={targetUser.avatar}
								alt=""
								class="h-12 w-12 shrink-0 rounded-full border-2 border-black"
							/>
						{:else}
							<div class="h-12 w-12 shrink-0 rounded-full border-2 border-black bg-gray-200"></div>
						{/if}
						<div class="min-w-0 flex-1">
							<div class="flex flex-wrap items-center gap-2">
								<h1 class="truncate text-xl font-bold">{targetUser.username || 'unknown'}</h1>
								<span
									class="rounded-full px-2 py-0.5 text-xs font-bold {getRoleBadgeColor(
										targetUser.role
									)}"
								>
									{targetUser.role}
								</span>
							</div>
							{#if targetUser.email}
								<p class="truncate text-sm text-gray-600">{targetUser.email}</p>
							{/if}
						</div>
					</div>
					<div class="mt-3 flex items-end justify-between gap-3">
						<div class="space-y-0.5 text-xs text-gray-500">
							<p>joined {new Date(targetUser.createdAt).toLocaleDateString()}</p>
						</div>
						<div class="flex items-center gap-1">
							<Spool size={20} />
							<span class="text-2xl font-bold">{targetUser.scraps}</span>
							<span class="text-xs text-gray-500">{$t.common.scraps}</span>
						</div>
					</div>
				</div>

				{#if stats}
					<div class="grid grid-cols-4 gap-2">
						<div class="rounded-xl border-2 border-black p-2 text-center">
							<p class="text-lg font-bold">{stats.total}</p>
							<p class="text-[11px] leading-tight text-gray-500">projects</p>
						</div>
						<div class="rounded-xl border-2 border-black p-2 text-center">
							<p class="text-lg font-bold text-green-600">{stats.shipped}</p>
							<p class="text-[11px] leading-tight text-gray-500">shipped</p>
						</div>
						<div class="rounded-xl border-2 border-black p-2 text-center">
							<p class="text-lg font-bold text-yellow-600">{stats.waitingForReview}</p>
							<p class="text-[11px] leading-tight text-gray-500">in review</p>
						</div>
						<div class="rounded-xl border-2 border-black p-2 text-center">
							<p class="text-lg font-bold">{formatHours(stats.totalHours)}h</p>
							<p class="text-[11px] leading-tight text-gray-500">hours</p>
						</div>
					</div>
				{/if}

				{#if currentUser?.role === 'admin' || currentUser?.role === 'creator'}
					<div class="flex flex-col gap-2">
						{#if targetUser.slackId}
							<a
								href="https://app.slack.com/client/E09V59WQY1E/{targetUser.slackId}"
								target="_blank"
								rel="noopener noreferrer"
								title={targetUser.slackId}
								class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 hover:border-dashed"
							>
								<MessageCircle size={16} />
								<span>slack DM</span>
							</a>
						{:else}
							<span
								class="flex w-full cursor-not-allowed items-center justify-center gap-2 rounded-full border-4 border-dashed border-gray-300 px-3 py-1.5 text-sm font-bold text-gray-400"
								title="no slack account linked"
							>
								<MessageCircle size={16} />
								<span>slack DM</span>
							</span>
						{/if}
						{#if hackatimeUserId}
							<a
								href="https://telescreen.hackclub.com/workbench/hackatime/overview?u={hackatimeUserId}"
								target="_blank"
								rel="noopener noreferrer"
								class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 hover:border-dashed"
							>
								<Monitor size={16} />
								<span>telescreen</span>
							</a>
						{:else}
							<span
								class="flex w-full cursor-not-allowed items-center justify-center gap-2 rounded-full border-4 border-dashed border-gray-300 px-3 py-1.5 text-sm font-bold text-gray-400"
								title="no hackatime account found"
							>
								<Monitor size={16} />
								<span>telescreen</span>
							</span>
						{/if}
						<button
							onclick={() => openActionModal('adjust')}
							class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black px-3 py-1.5 text-sm font-bold transition-all duration-200 hover:border-dashed"
						>
							<Scale size={16} />
							<span>change balance</span>
						</button>
					</div>
				{/if}

				{#if hackatimeBanned}
					<div class="rounded-2xl border-4 border-red-600 bg-red-50 p-3">
						<div class="flex items-center gap-3">
							<ShieldAlert size={20} class="text-red-600" />
							<div>
								<p class="font-bold text-red-800">hackatime banned</p>
								<p class="text-sm text-red-700">
									this user is banned on hackatime. they will be redirected to fraud.hackclub.com on
									login.
								</p>
							</div>
						</div>
					</div>
				{/if}
				{#if hackatimeSuspected}
					<div class="rounded-2xl border-4 border-orange-500 bg-orange-50 p-3">
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

				<div class="rounded-2xl border-4 border-black bg-yellow-50 p-4">
					<h2 class="mb-3 text-lg font-bold">admin settings</h2>
					<div class="space-y-4">
						{#if currentUser?.role === 'admin' || currentUser?.role === 'creator'}
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
										banning will redirect this user to fraud.hackclub.com on login
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

						<div class="flex items-center gap-3">
							<button
								onclick={saveChanges}
								disabled={saving}
								class="cursor-pointer rounded-full bg-black px-6 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
							>
								{saving ? $t.common.saving : $t.project.saveChanges}
							</button>
							{#if currentUser?.role === 'creator'}
								<button
									onclick={() => (showDeleteUserConfirm = true)}
									disabled={deletingUser}
									class="cursor-pointer rounded-full border-4 border-red-600 px-6 py-2 font-bold text-red-600 transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
								>
									delete user
								</button>
							{/if}
						</div>
					</div>
				</div>

				<div class="rounded-2xl border-4 border-black p-4">
					<h2 class="mb-3 text-lg font-bold">
						shop slots ({retainedShop?.used ?? 0}/{retainedShop?.cap ?? 0})
					</h2>
					{#if !retainedShop || retainedShop.items.length === 0}
						<p class="text-gray-500">no items retained</p>
					{:else}
						<ul class="divide-y divide-gray-200">
							{#each retainedShop.items as item}
								<li class="flex items-center gap-3 py-2 text-sm">
									{#if item.image}
										<img src={item.image} alt="" class="h-8 w-8 rounded object-cover" />
									{/if}
									<span class="truncate">{item.name}</span>
								</li>
							{/each}
						</ul>
					{/if}
				</div>
			</aside>

			<div class="min-w-0 space-y-6">
				<div class="rounded-2xl border-4 border-black p-6">
					<h2 class="mb-4 text-xl font-bold">{$t.profile.projects} ({projects.length})</h2>
					{#if projects.length === 0}
						<p class="text-gray-500">{$t.profile.noProjectsFound}</p>
					{:else}
						<ul class="divide-y divide-gray-200">
							{#each projects as project}
								{@const statusTag = getStatusTag(project.status)}
								<li>
									<a
										href="/admin/reviews/{project.id}"
										class="flex cursor-pointer items-center justify-between gap-3 py-2 text-sm hover:underline {project.deleted
											? 'opacity-50'
											: ''}"
									>
										<span class="truncate">
											{project.name}
											{#if project.deleted}<span class="text-red-500">(deleted)</span>{/if}
										</span>
										<span class="flex shrink-0 items-center gap-3 text-gray-500">
											<span>{formatHours(project.hoursOverride ?? project.hours)}h</span>
											{#if project.status === 'shipped' && project.scrapsAwarded > 0}
												{@const paid = !!project.scrapsPaidAt || project.scrapsPaidAmount > 0}
												<span
													class="font-bold {paid ? 'text-green-600' : 'text-yellow-600'}"
													title={paid ? 'scraps paid out' : 'approved, not paid out yet'}
													>+{project.scrapsPaidAmount > 0
														? project.scrapsPaidAmount
														: project.scrapsAwarded}{paid ? '' : ' pending'}</span
												>
											{/if}
											<span>{project.deleted ? 'deleted' : statusTag.label}</span>
											{#if project.payoutRoll}
												{@const roll = project.payoutRoll}
												<span title="bonus payout roll on {roll.baseScraps} scraps">
													{#if roll.roll1 === null}{roll.status === 'final'
															? "didn't roll · 1.00x"
															: "hasn't rolled yet"}{:else}rolled {roll.roll1.toFixed(
															2
														)}x{/if}{#if roll.roll2 !== null}
														→ {roll.roll2.toFixed(2)}x{/if}
													{#if roll.roll1 === null}{:else if roll.delta !== null}
														<span
															class="font-bold {roll.delta > 0
																? 'text-green-600'
																: roll.delta < 0
																	? 'text-red-600'
																	: ''}">({roll.delta > 0 ? '+' : ''}{roll.delta})</span
														>
													{:else}
														(deciding)
													{/if}
												</span>
											{/if}
											{#if project.status === 'shipped' && (currentUser?.role === 'admin' || currentUser?.role === 'creator')}
												<button
													onclick={(e) => {
														e.preventDefault();
														e.stopPropagation();
														showUnshipConfirm = project.id;
													}}
													class="cursor-pointer rounded-full border-2 border-red-600 px-2 py-0.5 text-xs font-bold text-red-600 transition-all duration-200 hover:border-dashed"
												>
													unship
												</button>
											{/if}
											<span>{new Date(project.updatedAt).toLocaleDateString()}</span>
										</span>
									</a>
								</li>
							{/each}
						</ul>
					{/if}
				</div>

				{#if currentUser?.role === 'admin' || currentUser?.role === 'creator'}
					<div class="rounded-2xl border-4 border-black p-6">
						<div class="mb-4 flex flex-wrap items-center justify-between gap-3">
							<h2 class="text-xl font-bold">
								orders ({orders.length})
								<span class="text-sm font-normal text-gray-500"
									>· {pendingOrders.length} pending</span
								>
							</h2>
							<div class="flex flex-wrap items-center gap-2">
								<select
									bind:value={orderFilter}
									aria-label="filter orders"
									class="cursor-pointer rounded-full border-2 border-black bg-white px-3 py-1 text-sm font-bold focus:border-dashed focus:outline-none"
								>
									<option value="pending">pending</option>
									<option value="all">all</option>
									<option value="fulfilled">fulfilled</option>
									<option value="cancelled">cancelled</option>
								</select>
								<select
									bind:value={orderSort}
									aria-label="sort orders"
									class="cursor-pointer rounded-full border-2 border-black bg-white px-3 py-1 text-sm font-bold focus:border-dashed focus:outline-none"
								>
									<option value="newest">newest</option>
									<option value="oldest">oldest</option>
									<option value="price_desc">price high → low</option>
									<option value="price_asc">price low → high</option>
									<option value="status">status</option>
									<option value="type">type</option>
								</select>
								<button
									onclick={() => openActionModal('reject')}
									disabled={pendingOrders.length === 0}
									class="inline-flex cursor-pointer items-center gap-2 rounded-full border-4 border-red-600 px-3 py-1 text-sm font-bold text-red-600 transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:border-gray-300 disabled:text-gray-400"
								>
									<XCircle size={16} />
									<span>reject all ({pendingOrders.length})</span>
								</button>
							</div>
						</div>
						{#if sortedOrders.length === 0}
							<p class="text-gray-500">
								{orderFilter === 'all' ? 'no orders' : `no ${orderFilter} orders`}
							</p>
						{:else}
							<ul class="divide-y divide-gray-200">
								{#each sortedOrders as order (order.id)}
									<li>
										<a
											href="/admin/orders/{order.id}"
											class="flex cursor-pointer items-center justify-between gap-3 py-2 text-sm hover:underline {order.status ===
												'cancelled' || order.status === 'deleted'
												? 'opacity-60'
												: ''}"
										>
											<span class="flex min-w-0 items-center gap-3">
												{#if order.itemImage}
													<img src={order.itemImage} alt="" class="h-8 w-8 rounded object-cover" />
												{/if}
												<span class="truncate">
													{order.itemName ?? 'unknown item'}{order.size ? ` · ${order.size}` : ''}
													{#if order.quantity > 1}× {order.quantity}{/if}
												</span>
											</span>
											<span class="flex shrink-0 items-center gap-3 text-gray-500">
												<span>{order.orderType.replace(/_/g, ' ')}</span>
												<span>{order.totalPrice} scraps</span>
												<span
													class="rounded-full px-2 py-0.5 text-xs font-bold {orderStatusClass(
														order
													)}">{orderStatusLabel(order)}</span
												>
												<span>{new Date(order.createdAt).toLocaleDateString()}</span>
											</span>
										</a>
									</li>
								{/each}
							</ul>
						{/if}
					</div>
				{/if}

				{#if currentUser?.role === 'admin' || currentUser?.role === 'creator'}
					<!-- Financial Timeline -->
					<div class="rounded-2xl border-4 border-black p-6">
						<div class="mb-4 flex items-center justify-between">
							<h2 class="flex items-center gap-2 text-xl font-bold">
								<History size={20} />
								financial timeline
							</h2>
						</div>

						{#if timelineLoading}
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
												{#if (event.type.startsWith('shop_') && event.orderId) || (event.type === 'bonus' && event.bonusId)}
													<button
														onclick={() => confirmTimelineDelete(event)}
														disabled={undoingOrder === event.orderId ||
															deletingBonus === event.bonusId}
														class="cursor-pointer rounded-full border-2 border-red-600 px-2 py-1 text-xs font-bold text-red-600 transition-all duration-200 hover:border-dashed disabled:opacity-50"
														title="delete"
													>
														{#if undoingOrder === event.orderId || deletingBonus === event.bonusId}
															...
														{:else}
															<Trash2 size={12} />
														{/if}
													</button>
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
			</div>
		</div>
	{/if}
</div>

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

{#if actionModal}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && !actionSaving && (actionModal = null)}
		onkeydown={(e) => e.key === 'Escape' && !actionSaving && (actionModal = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-2 text-2xl font-bold">
				{actionModal === 'reject' ? 'reject all orders' : 'adjust balance'}
			</h2>
			{#if actionModal === 'reject'}
				<p class="mb-4 text-sm text-gray-600">
					cancels all {pendingOrders.length} unfulfilled order(s) for {targetUser?.username}.
					consolation (lost roll) orders are never refunded. the user gets one DM with the reason
					below.
				</p>
				<label class="mb-4 flex cursor-pointer items-center gap-2 text-sm font-bold">
					<input type="checkbox" bind:checked={actionRefund} class="h-4 w-4 cursor-pointer" />
					refund scraps for purchases and wins
				</label>
			{:else}
				<p class="mb-4 text-sm text-gray-600">
					current balance: {targetUser?.scraps} scraps. the user gets a DM with the reason below.
				</p>
			{/if}

			{#if actionError}
				<div class="mb-4 rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
					{actionError}
				</div>
			{/if}

			<div class="space-y-4">
				{#if actionModal === 'adjust'}
					<div>
						<label for="actionAmount" class="mb-1 block text-sm font-bold"
							>amount <span class="text-red-500">*</span></label
						>
						<input
							id="actionAmount"
							type="number"
							bind:value={actionAmount}
							placeholder="e.g. 100 or -50"
							class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						/>
						<p class="mt-1 text-xs text-gray-500">negative numbers deduct scraps</p>
					</div>
				{/if}
				<div>
					<label for="actionInternalReason" class="mb-1 block text-sm font-bold"
						>reason (internal) <span class="text-red-500">*</span></label
					>
					<textarea
						id="actionInternalReason"
						bind:value={actionInternalReason}
						rows="3"
						placeholder="only admins see this"
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
				</div>
				<div>
					<label for="actionUserReason" class="mb-1 block text-sm font-bold"
						>reason to user <span class="text-red-500">*</span></label
					>
					<textarea
						id="actionUserReason"
						bind:value={actionUserReason}
						rows="3"
						placeholder="sent to the user as a slack DM"
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
				</div>
			</div>

			<div class="mt-6 flex gap-3">
				<button
					onclick={() => (actionModal = null)}
					disabled={actionSaving}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={submitAction}
					disabled={actionSaving ||
						actionInternalReason.trim().length < 3 ||
						actionUserReason.trim().length < 3 ||
						(actionModal === 'adjust' && !actionAmount)}
					class="flex-1 cursor-pointer rounded-full px-4 py-2 font-bold text-white transition-all duration-200 disabled:cursor-not-allowed disabled:opacity-50 {actionModal ===
					'reject'
						? 'bg-red-600 hover:bg-red-700'
						: 'bg-black hover:bg-gray-800'}"
				>
					{actionSaving
						? $t.common.saving
						: actionModal === 'reject'
							? 'reject all + DM'
							: 'adjust + DM'}
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Timeline Delete Confirmation Modal -->
{#if showDeleteConfirm}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (showDeleteConfirm = null)}
		onkeydown={(e) => e.key === 'Escape' && (showDeleteConfirm = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">
				delete {showDeleteConfirm.type === 'bonus' ? 'bonus' : 'order'}
			</h2>
			<p class="mb-6 text-gray-600">
				{#if showDeleteConfirm.type === 'bonus'}
					this will permanently delete this bonus entry from the database. the user's balance will
					be recalculated.
				{:else}
					this will permanently delete this order and all associated records (refinery upgrades,
					rolls, penalties). item stock will be restored.
				{/if}
			</p>
			<div class="flex gap-3">
				<button
					onclick={() => (showDeleteConfirm = null)}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
				>
					cancel
				</button>
				<button
					onclick={executeTimelineDelete}
					class="flex-1 cursor-pointer rounded-full border-4 border-red-600 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					delete
				</button>
			</div>
		</div>
	</div>
{/if}

{#if showDeleteUserConfirm}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (showDeleteUserConfirm = false)}
		onkeydown={(e) => e.key === 'Escape' && (showDeleteUserConfirm = false)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">delete user</h2>
			<p class="mb-6 text-gray-600">
				are you sure you want to permanently delete <strong
					>{targetUser?.username || 'this user'}</strong
				>? this will remove all their data including projects, orders, bonuses, and sessions. this
				cannot be undone.
			</p>
			<div class="flex gap-3">
				<button
					onclick={() => (showDeleteUserConfirm = false)}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
				>
					cancel
				</button>
				<button
					onclick={deleteUser}
					disabled={deletingUser}
					class="flex-1 cursor-pointer rounded-full border-4 border-red-600 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{deletingUser ? 'deleting...' : 'delete permanently'}
				</button>
			</div>
		</div>
	</div>
{/if}
