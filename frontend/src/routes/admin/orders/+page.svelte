<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		Check,
		X,
		Package,
		Clock,
		Truck,
		CheckCircle,
		XCircle,
		Trash2,
		ChevronDown,
		ChevronUp,
		Search
	} from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';

	interface ShippingAddress {
		firstName: string;
		lastName: string;
		address1: string;
		address2: string | null;
		city: string;
		state: string;
		postalCode: string;
		country: string;
		phone: string | null;
	}

	interface Order {
		id: number;
		quantity: number;
		pricePerItem: number;
		totalPrice: number;
		status: string;
		orderType: string;
		notes: string | null;
		isFulfilled: boolean;
		shippingAddress: string | null;
		phone: string | null;
		createdAt: string;
		itemId: number;
		itemName: string;
		itemImage: string;
		userId: number;
		username: string;
		slackId: string | null;
	}

	function parseShippingAddress(addr: string | null): ShippingAddress | null {
		if (!addr) return null;
		try {
			return JSON.parse(addr);
		} catch {
			return null;
		}
	}

	function formatName(addr: ShippingAddress): string {
		return `${addr.firstName} ${addr.lastName}`.trim();
	}

	interface User {
		id: number;
		role: string;
	}

	let user = $state<User | null>(null);
	let orders = $state<Order[]>([]);
	let loading = $state(true);
	let filter = $state<'all' | 'pending' | 'fulfilled'>('all');
	let searchQuery = $state('');
	let dateFrom = $state('');
	let dateTo = $state('');
	let confirmRevert = $state<Order | null>(null);
	let confirmDelete = $state<Order | null>(null);
	// short reason for deletion (shown in admin logs) - required by server when deleting/reverting
	let confirmReason = $state('');
	let actionLoading = $state(false);
	let expandedOrders = $state<Record<number, boolean>>({});
	let collapsedGroups = $state<Record<string, boolean>>({});
	let lastDeleted = $state<Order | null>(null);
	let lastDeletedTimer = $state<number | null>(null);
	let lastDeletedError = $state<string | null>(null);

	let filteredOrders = $derived.by(() => {
		let result =
			filter === 'all'
				? orders
				: filter === 'pending'
					? orders.filter((o) => !o.isFulfilled)
					: orders.filter((o) => o.isFulfilled);

		if (searchQuery.trim()) {
			const q = searchQuery.trim().toLowerCase();
			result = result.filter((o) => {
				if (o.username.toLowerCase().includes(q)) return true;
				if (o.slackId && o.slackId.toLowerCase().includes(q)) return true;
				const addr = parseShippingAddress(o.shippingAddress);
				if (addr) {
					const fullName = formatName(addr).toLowerCase();
					if (fullName.includes(q)) return true;
				}
				return false;
			});
		}

		if (dateFrom) {
			const from = new Date(dateFrom);
			from.setHours(0, 0, 0, 0);
			result = result.filter((o) => new Date(o.createdAt) >= from);
		}

		if (dateTo) {
			const to = new Date(dateTo);
			to.setHours(23, 59, 59, 999);
			result = result.filter((o) => new Date(o.createdAt) <= to);
		}

		return result;
	});

	let groupedOrders = $derived(
		Object.values(
			filteredOrders.reduce(
				(acc, order) => {
					const groupKey = order.orderType === 'consolation' ? 'Consolations' : order.itemName;
					if (!acc[groupKey]) {
						acc[groupKey] = { itemName: groupKey, itemImage: order.itemImage, orders: [] };
					}
					acc[groupKey].orders.push(order);
					return acc;
				},
				{} as Record<string, { itemName: string; itemImage: string; orders: Order[] }>
			)
		)
			.map((group) => {
				group.orders.sort(
					(a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
				);
				return group;
			})
			.sort((a, b) => {
				if (a.orders.length === 0) return 1;
				if (b.orders.length === 0) return -1;
				return (
					new Date(a.orders[0].createdAt).getTime() - new Date(b.orders[0].createdAt).getTime()
				);
			})
	);

	onMount(async () => {
		user = await getUser();
		if (!user || user.role !== 'admin') {
			goto('/dashboard');
			return;
		}

		await fetchOrders();
	});

	async function fetchOrders() {
		loading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders`, {
				credentials: 'include'
			});
			if (response.ok) {
				orders = await response.json();
			}
		} catch (e) {
			console.error('Failed to fetch orders:', e);
		} finally {
			loading = false;
		}
	}

	async function toggleFulfilled(order: Order) {
		actionLoading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}`, {
				method: 'PATCH',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ isFulfilled: !order.isFulfilled })
			});
			if (response.ok) {
				orders = orders.map((o) => (o.id === order.id ? { ...o, isFulfilled: !o.isFulfilled } : o));
			}
		} catch (e) {
			console.error('Failed to update order:', e);
		} finally {
			actionLoading = false;
		}
	}

	async function deleteOrder(order: Order) {
		actionLoading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}`, {
				method: 'DELETE',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ reason: confirmReason })
			});
			const text = await response.text();
			let json: any = null;
			try {
				json = JSON.parse(text);
			} catch {
				// ignore parse error
			}

			if (response.ok) {
				// remove from visible list
				orders = orders.filter((o) => o.id !== order.id);
				// keep a reference so the admin can revert shortly after deletion
				lastDeleted = order;
				lastDeletedError = null;
				// clear any existing timer
				if (lastDeletedTimer) {
					clearTimeout(lastDeletedTimer);
				}
				// allow undo for 30 seconds
				lastDeletedTimer = window.setTimeout(() => {
					lastDeleted = null;
					lastDeletedTimer = null;
					lastDeletedError = null;
				}, 30000);
			} else {
				const err = (json && (json.error || json.message)) || text || 'failed to delete';
				console.error('Failed to delete order:', err);
			}
		} catch (e) {
			console.error('Failed to delete order:', e);
		} finally {
			actionLoading = false;
			confirmDelete = null;
			confirmReason = '';
		}
	}

	async function restoreDeletedOrder(order: Order) {
		if (!order) return;
		actionLoading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}/restore`, {
				method: 'POST',
				credentials: 'include'
			});
			const text = await response.text();
			let json: any = null;
			try {
				json = JSON.parse(text);
			} catch {
				// ignore
			}
			if (response.ok) {
				// refetch orders to ensure consistent ordering & data
				await fetchOrders();
				// clear undo state
				if (lastDeletedTimer) {
					clearTimeout(lastDeletedTimer);
				}
				lastDeleted = null;
				lastDeletedTimer = null;
				lastDeletedError = null;
			} else {
				const err = (json && (json.error || json.message)) || text || 'restore failed';
				lastDeletedError = String(err);
				console.error('Failed to restore archived order:', err);
			}
		} catch (e) {
			lastDeletedError = String(e instanceof Error ? e.message : e);
			console.error('Failed to restore archived order:', e);
		} finally {
			actionLoading = false;
		}
	}

	function formatDate(dateString: string) {
		return new Date(dateString).toLocaleDateString('en-US', {
			month: 'short',
			day: 'numeric',
			year: 'numeric',
			hour: '2-digit',
			minute: '2-digit'
		});
	}

	function getStatusIcon(status: string) {
		switch (status) {
			case 'pending':
				return Clock;
			case 'processing':
				return Package;
			case 'shipped':
				return Truck;
			case 'delivered':
				return CheckCircle;
			case 'cancelled':
				return XCircle;
			default:
				return Clock;
		}
	}

	function getStatusColor(status: string) {
		switch (status) {
			case 'pending':
				return 'bg-yellow-100 text-yellow-700 border-yellow-600';
			case 'processing':
				return 'bg-blue-100 text-blue-700 border-blue-600';
			case 'shipped':
				return 'bg-purple-100 text-purple-700 border-purple-600';
			case 'delivered':
				return 'bg-green-100 text-green-700 border-green-600';
			case 'cancelled':
				return 'bg-red-100 text-red-700 border-red-600';
			default:
				return 'bg-gray-100 text-gray-700 border-gray-600';
		}
	}
</script>

<svelte:head>
	<title>{$t.nav.orders} - {$t.nav.admin} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-6xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-8 flex items-center justify-between">
		<div>
			<h1 class="mb-2 text-4xl font-bold md:text-5xl">{$t.nav.orders}</h1>
			<p class="text-lg text-gray-600">{$t.admin.manageOrdersAndFulfillment}</p>
		</div>
	</div>

	<!-- Filter tabs -->
	<div class="mb-6 flex flex-wrap items-center justify-between gap-4">
		<div class="flex gap-2">
			<button
				onclick={() => (filter = 'all')}
				class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {filter ===
				'all'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{$t.admin.all} ({orders.length})
			</button>
			<button
				onclick={() => (filter = 'pending')}
				class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {filter ===
				'pending'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{$t.admin.pending} ({orders.filter((o) => !o.isFulfilled).length})
			</button>
			<button
				onclick={() => (filter = 'fulfilled')}
				class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {filter ===
				'fulfilled'
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				{$t.admin.fulfilled} ({orders.filter((o) => o.isFulfilled).length})
			</button>
		</div>

		<!-- Search and Date Filters -->
		<div class="flex flex-wrap items-end gap-3">
			<div class="relative flex-1" style="min-width: 200px;">
				<Search size={18} class="absolute top-1/2 left-4 -translate-y-1/2 text-gray-400" />
				<input
					type="text"
					placeholder="search by name or slack id..."
					bind:value={searchQuery}
					class="w-full rounded-full border-4 border-black py-2 pr-4 pl-10 font-bold transition-all duration-200 placeholder:text-gray-400 focus:border-dashed focus:ring-0 focus:outline-none"
				/>
			</div>
			<div class="flex items-end gap-2">
				<div class="flex flex-col">
					<label for="date-from" class="mb-1 text-xs font-bold text-gray-500 uppercase">from</label>
					<input
						id="date-from"
						type="date"
						bind:value={dateFrom}
						class="rounded-xl border-4 border-black px-3 py-2 font-bold transition-all duration-200 focus:border-dashed focus:outline-none"
					/>
				</div>
				<div class="flex flex-col">
					<label for="date-to" class="mb-1 text-xs font-bold text-gray-500 uppercase">to</label>
					<input
						id="date-to"
						type="date"
						bind:value={dateTo}
						class="rounded-xl border-4 border-black px-3 py-2 font-bold transition-all duration-200 focus:border-dashed focus:outline-none"
					/>
				</div>
				{#if dateFrom || dateTo}
					<button
						onclick={() => {
							dateFrom = '';
							dateTo = '';
						}}
						class="cursor-pointer rounded-xl border-4 border-black px-3 py-2 font-bold transition-all duration-200 hover:border-dashed"
						title="clear dates"
					>
						<X size={18} />
					</button>
				{/if}
			</div>
		</div>
	</div>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if filteredOrders.length === 0}
		<div class="py-12 text-center text-gray-500">no orders found</div>
	{:else}
		<div class="flex flex-col gap-8">
			{#each groupedOrders as group}
				{@const isConsolations = group.itemName === 'Consolations'}
				{@const isCollapsed = collapsedGroups[group.itemName] ?? isConsolations}
				<div
					class="rounded-3xl border-4 border-black bg-white shadow-[8px_8px_0px_0px_rgba(0,0,0,1)]"
				>
					<button
						onclick={() => {
							collapsedGroups[group.itemName] = !isCollapsed;
						}}
						class="flex w-full cursor-pointer items-center justify-between gap-4 p-6 hover:bg-black/5 {isCollapsed
							? 'rounded-3xl'
							: 'rounded-t-3xl'} transition-colors"
					>
						<div class="flex items-center gap-4">
							<img
								src={group.itemImage}
								alt={group.itemName}
								class="h-16 w-16 shrink-0 rounded-lg border-2 border-black object-cover"
							/>
							<div class="text-left">
								<h2 class="text-2xl font-bold md:text-3xl">{group.itemName}</h2>
								<p class="font-bold text-gray-500">
									{group.orders.length}
									{group.orders.length === 1 ? 'order' : 'orders'}
								</p>
							</div>
						</div>
						<div class="text-gray-400">
							{#if isCollapsed}
								<ChevronDown size={24} />
							{:else}
								<ChevronUp size={24} />
							{/if}
						</div>
					</button>

					{#if !isCollapsed}
						<div class="grid gap-4 px-6 pt-4 pb-6">
							{#each group.orders as order}
								{@const StatusIcon = getStatusIcon(order.status)}
								<div
									class="overflow-hidden rounded-2xl border-4 border-black transition-colors {order.isFulfilled
										? 'bg-green-50'
										: 'bg-white'}"
								>
									<!-- Clickable Summary Header -->
									<button
										onclick={() => (expandedOrders[order.id] = !expandedOrders[order.id])}
										class="flex w-full cursor-pointer items-center justify-between gap-4 p-4 text-left hover:bg-black/5"
									>
										<div class="flex flex-wrap items-center gap-3">
											<a
												href="/admin/users/{order.userId}"
												onclick={(e) => e.stopPropagation()}
												class="text-lg font-bold hover:underline"
											>
												@{order.username}
											</a>
											<span class="text-gray-400">•</span>
											<span class="text-gray-600">{formatDate(order.createdAt)}</span>
											<span class="text-gray-400">•</span>
											<span class="font-bold">{order.totalPrice} scraps</span>
											{#if order.quantity > 1}
												<span class="text-gray-400">•</span>
												<span class="font-bold text-gray-500">×{order.quantity}</span>
											{/if}
										</div>

										<div class="flex shrink-0 items-center gap-2">
											<span
												class="hidden items-center gap-1 rounded-full border-2 px-2 py-0.5 text-xs font-bold md:inline-flex {getStatusColor(
													order.status
												)}"
											>
												<StatusIcon size={12} />
												{order.status}
											</span>
											{#if order.isFulfilled}
												<span
													class="hidden items-center gap-1 rounded-full border-2 border-green-600 bg-green-100 px-2 py-0.5 text-xs font-bold text-green-700 md:inline-flex"
												>
													<Check size={12} />
													fulfilled
												</span>
											{/if}
											<div class="ml-2 text-gray-400">
												{#if expandedOrders[order.id]}
													<ChevronUp size={20} />
												{:else}
													<ChevronDown size={20} />
												{/if}
											</div>
										</div>
									</button>

									<!-- Expanded Info Panel -->
									{#if expandedOrders[order.id]}
										<div class="border-t-4 border-dashed border-gray-200 p-4">
											<!-- Status Tags for Mobile -->
											<div class="mb-4 flex flex-wrap gap-2 md:hidden">
												<span
													class="inline-flex items-center gap-1 rounded-full border-2 px-2 py-0.5 text-xs font-bold {getStatusColor(
														order.status
													)}"
												>
													<StatusIcon size={12} />
													{order.status}
												</span>
												{#if order.isFulfilled}
													<span
														class="inline-flex items-center gap-1 rounded-full border-2 border-green-600 bg-green-100 px-2 py-0.5 text-xs font-bold text-green-700"
													>
														<Check size={12} />
														fulfilled
													</span>
												{/if}
											</div>

											<div
												class="flex flex-col gap-6 md:flex-row md:items-start md:justify-between"
											>
												<div class="min-w-0 flex-1 text-sm">
													{#if order.notes}
														<p class="mb-3 text-gray-600"><strong>Notes:</strong> {order.notes}</p>
													{/if}

													{#if parseShippingAddress(order.shippingAddress)}
														{@const addr = parseShippingAddress(order.shippingAddress)!}
														<!-- svelte-ignore a11y_no_static_element_interactions -->
														<div
															class="group/addr rounded-xl border-2 border-gray-300 bg-white p-4"
														>
															<p class="mb-2 text-xs font-bold text-gray-500 uppercase">
																shipping address
															</p>
															<div
																class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 blur-sm transition-all duration-300 select-none group-hover/addr:blur-none group-hover/addr:select-auto"
															>
																<span class="font-bold text-gray-500">name</span>
																<span>{formatName(addr)}</span>
																<span class="font-bold text-gray-500">address 1</span>
																<span>{addr.address1}</span>
																{#if addr.address2}
																	<span class="font-bold text-gray-500">address 2</span>
																	<span>{addr.address2}</span>
																{/if}
																<span class="font-bold text-gray-500">city</span>
																<span>{addr.city}</span>
																<span class="font-bold text-gray-500">state</span>
																<span>{addr.state}</span>
																<span class="font-bold text-gray-500">zip</span>
																<span>{addr.postalCode}</span>
																<span class="font-bold text-gray-500">country</span>
																<span>{addr.country}</span>
																{#if order.phone || addr.phone}
																	<span class="font-bold text-gray-500">phone</span>
																	<span>{order.phone || addr.phone}</span>
																{/if}
															</div>
														</div>
													{:else if order.orderType === 'win'}
														<div class="rounded-xl border-2 border-yellow-300 bg-yellow-100 p-4">
															<p class="font-bold text-yellow-700">no shipping address provided</p>
														</div>
													{/if}
													{#if order.phone && !parseShippingAddress(order.shippingAddress)}
														<div class="mt-2 rounded-xl border-2 border-gray-300 bg-white p-4">
															<div class="grid grid-cols-[auto_1fr] gap-x-4">
																<span class="font-bold text-gray-500">phone</span>
																<span>{order.phone}</span>
															</div>
														</div>
													{/if}
												</div>

												<!-- Actions -->
												<div class="flex shrink-0 flex-col gap-3 md:w-48">
													<button
														onclick={() => toggleFulfilled(order)}
														class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {order.isFulfilled
															? 'bg-gray-200 hover:border-dashed hover:bg-gray-300'
															: 'bg-green-500 text-white hover:border-dashed hover:bg-green-600'}"
													>
														{#if order.isFulfilled}
															<X size={16} />
															{$t.admin.unfulfill}
														{:else}
															<Check size={16} />
															{$t.admin.fulfill}
														{/if}
													</button>
													<button
														onclick={() => (confirmDelete = order)}
														class="flex w-full cursor-pointer items-center justify-center gap-1 rounded-full border-4 border-red-600 px-3 py-2 font-bold text-red-600 transition-all duration-200 hover:border-dashed"
														title="delete order"
													>
														<Trash2 size={16} />
														delete order
													</button>
												</div>
											</div>
										</div>
									{/if}
								</div>
							{/each}
						</div>
					{/if}
				</div>
			{/each}
		</div>
	{/if}
</div>

<!-- Delete Confirmation Modal -->
{#if confirmDelete}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (confirmDelete = null)}
		onkeydown={(e) => e.key === 'Escape' && (confirmDelete = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">delete order</h2>
			<p class="mb-2 text-gray-600">
				this will permanently delete the order for <span class="font-bold"
					>@{confirmDelete.username}</span
				> and remove associated refinery/roll/penalty records from their financial timeline. No refund
				or bonus will be issued.
			</p>
			<p class="mb-6 text-sm font-bold text-red-600">
				this action can be reverted for a short time (undo available) but is otherwise destructive.
			</p>
			<label for="confirm-reason" class="mb-2 block text-sm font-bold text-gray-700"
				>reason (min 3 chars)</label
			>
			<textarea
				id="confirm-reason"
				aria-describedby="confirm-reason-error"
				aria-required="true"
				aria-invalid={confirmReason.trim().length > 0 && confirmReason.trim().length < 3}
				bind:value={confirmReason}
				class="mb-2 w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
				rows="3"
				placeholder="brief reason for deleting this order (required)"
			></textarea>
			{#if confirmReason && confirmReason.trim().length > 0 && confirmReason.trim().length < 3}
				<p id="confirm-reason-error" class="mb-4 text-sm text-red-600">
					reason must be at least 3 characters
				</p>
			{:else}
				<div class="mb-4" aria-hidden="true"></div>
			{/if}
			<div class="flex gap-3">
				<button
					onclick={() => ((confirmDelete = null), (confirmReason = ''))}
					disabled={actionLoading}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={() => {
						// basic client-side validation to ensure server receives a short reason
						if (!confirmReason || confirmReason.trim().length < 3) {
							actionLoading = false;
							// small UX: keep modal open and don't proceed
							return;
						}
						confirmDelete && deleteOrder(confirmDelete);
					}}
					disabled={actionLoading}
					class="flex-1 cursor-pointer rounded-full border-4 border-red-600 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{actionLoading ? '...' : 'delete permanently'}
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Undo Toast (shows after a deletion, allows quick restore) -->
{#if lastDeleted}
	<div
		role="status"
		aria-live="polite"
		aria-atomic="true"
		class="fixed right-6 bottom-6 z-50 flex items-center gap-4 rounded-2xl border-4 border-black bg-white p-4 shadow-lg"
	>
		<div>
			<p class="font-bold">Order deleted</p>
			<p class="text-sm text-gray-600">
				Deleted order for <span class="font-bold">@{lastDeleted.username}</span>. You can revert
				this action for a short time.
			</p>
			{#if lastDeletedError}
				<p class="text-sm text-red-600">{lastDeletedError}</p>
			{/if}
		</div>
		<div class="flex flex-col gap-2">
			<button
				onclick={() => {
					lastDeleted && restoreDeletedOrder(lastDeleted);
				}}
				disabled={actionLoading}
				class="rounded-full border-4 border-black bg-white px-4 py-2 font-bold hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
			>
				revert
			</button>
			<button
				onclick={() => {
					lastDeleted = null;
					if (lastDeletedTimer) {
						clearTimeout(lastDeletedTimer);
						lastDeletedTimer = null;
					}
					lastDeletedError = null;
				}}
				class="rounded-full border-4 border-gray-300 px-3 py-1 font-bold hover:border-dashed"
			>
				dismiss
			</button>
		</div>
	</div>
{/if}

<style>
	@keyframes float {
		0%,
		100% {
			transform: translateY(0);
		}
		50% {
			transform: translateY(-6px);
		}
	}
</style>
