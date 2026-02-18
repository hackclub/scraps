<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { Check, X, Package, Clock, Truck, CheckCircle, XCircle, Trash2, RotateCcw } from '@lucide/svelte';
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
	let confirmModal = $state<{ type: 'soft-delete' | 'permanent-delete'; order: Order } | null>(null);
	let actionLoading = $state(false);

	let activeOrders = $derived(orders.filter((o) => o.status !== 'deleted'));
	let deletedOrders = $derived(orders.filter((o) => o.status === 'deleted'));

	let filteredOrders = $derived(
		filter === 'all'
			? activeOrders
			: filter === 'pending'
				? activeOrders.filter((o) => !o.isFulfilled)
				: activeOrders.filter((o) => o.isFulfilled)
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
		}
	}

	async function softDeleteOrder(order: Order) {
		actionLoading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}/soft-delete`, {
				method: 'POST',
				credentials: 'include'
			});
			if (response.ok) {
				orders = orders.map((o) => (o.id === order.id ? { ...o, status: 'deleted' } : o));
			}
		} catch (e) {
			console.error('Failed to soft-delete order:', e);
		} finally {
			actionLoading = false;
			confirmModal = null;
		}
	}

	async function restoreOrder(order: Order) {
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}/restore`, {
				method: 'POST',
				credentials: 'include'
			});
			if (response.ok) {
				orders = orders.map((o) => (o.id === order.id ? { ...o, status: 'pending' } : o));
			}
		} catch (e) {
			console.error('Failed to restore order:', e);
		}
	}

	async function permanentDeleteOrder(order: Order) {
		actionLoading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			if (response.ok) {
				orders = orders.filter((o) => o.id !== order.id);
			}
		} catch (e) {
			console.error('Failed to permanently delete order:', e);
		} finally {
			actionLoading = false;
			confirmModal = null;
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
			case 'deleted':
				return Trash2;
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
			case 'deleted':
				return 'bg-gray-100 text-gray-700 border-gray-600';
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
	<div class="mb-6 flex gap-2">
		<button
			onclick={() => (filter = 'all')}
			class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {filter ===
			'all'
				? 'bg-black text-white'
				: 'hover:border-dashed'}"
		>
			{$t.admin.all} ({activeOrders.length})
		</button>
		<button
			onclick={() => (filter = 'pending')}
			class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {filter ===
			'pending'
				? 'bg-black text-white'
				: 'hover:border-dashed'}"
		>
			{$t.admin.pending} ({activeOrders.filter((o) => !o.isFulfilled).length})
		</button>
		<button
			onclick={() => (filter = 'fulfilled')}
			class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {filter ===
			'fulfilled'
				? 'bg-black text-white'
				: 'hover:border-dashed'}"
		>
			{$t.admin.fulfilled} ({activeOrders.filter((o) => o.isFulfilled).length})
		</button>
	</div>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if filteredOrders.length === 0}
		<div class="py-12 text-center text-gray-500">no orders found</div>
	{:else}
		<div class="grid gap-4">
			{#each filteredOrders as order}
				{@const StatusIcon = getStatusIcon(order.status)}
				<div class="rounded-2xl border-4 border-black p-4 {order.isFulfilled ? 'bg-green-50' : ''}">
					<div class="flex items-start gap-4">
						<!-- Item image -->
						<img
							src={order.itemImage}
							alt={order.itemName}
							class="h-16 w-16 shrink-0 rounded-lg border-2 border-black object-cover"
						/>

						<!-- Order details -->
						<div class="min-w-0 flex-1">
							<div class="mb-1 flex items-center gap-2">
								<h3 class="text-lg font-bold">{order.itemName}</h3>
								<span class="text-gray-500">&times;{order.quantity}</span>
							</div>

							<div class="mb-2 flex flex-wrap items-center gap-2">
								<a href="/admin/users/{order.userId}" class="text-sm font-bold hover:underline">
									@{order.username}
								</a>
								<span class="text-gray-400">&bull;</span>
								<span class="text-sm text-gray-500">{formatDate(order.createdAt)}</span>
								<span class="text-gray-400">&bull;</span>
								<span class="text-sm font-bold">{order.totalPrice} scraps</span>
							</div>

							<div class="flex flex-wrap items-center gap-2">
								<span
									class="inline-flex items-center gap-1 rounded-full border-2 px-2 py-0.5 text-xs font-bold {getStatusColor(
										order.status
									)}"
								>
									<StatusIcon size={12} />
									{order.status}
								</span>

								<span
									class="rounded-full border-2 px-2 py-0.5 text-xs font-bold {order.orderType ===
									'win'
										? 'border-purple-600 bg-purple-100 text-purple-700'
										: order.orderType === 'lootbox_win'
											? 'border-indigo-600 bg-indigo-100 text-indigo-700'
											: 'border-gray-600 bg-gray-100 text-gray-700'}"
								>
									{order.orderType}
								</span>

								{#if order.notes?.startsWith('[Lootbox:')}
									<span
										class="rounded-full border-2 border-indigo-600 bg-indigo-100 px-2 py-0.5 text-xs font-bold text-indigo-700"
									>
										{$t.lootbox.badge}
									</span>
								{/if}

								{#if order.isFulfilled}
									<span
										class="inline-flex items-center gap-1 rounded-full border-2 border-green-600 bg-green-100 px-2 py-0.5 text-xs font-bold text-green-700"
									>
										<Check size={12} />
										fulfilled
									</span>
								{/if}
							</div>

							{#if order.notes}
								<p class="mt-2 text-sm text-gray-600">{order.notes}</p>
							{/if}

							{#if parseShippingAddress(order.shippingAddress)}
								{@const addr = parseShippingAddress(order.shippingAddress)!}
								<div class="mt-2 rounded-lg border border-gray-300 bg-gray-100 p-3">
									<p class="mb-2 text-xs font-bold text-gray-500 uppercase">shipping address</p>
									<div class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
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
							{:else if order.orderType === 'win' || order.orderType === 'lootbox_win'}
								<div class="mt-2 rounded-lg border border-yellow-300 bg-yellow-100 p-2">
									<p class="text-xs font-bold text-yellow-700">no shipping address provided</p>
								</div>
							{/if}
							{#if order.phone && !parseShippingAddress(order.shippingAddress)}
								<div class="mt-2 rounded-lg border border-gray-300 bg-gray-100 p-3">
									<div class="grid grid-cols-[auto_1fr] gap-x-3 text-sm">
										<span class="font-bold text-gray-500">phone</span>
										<span>{order.phone}</span>
									</div>
								</div>
							{/if}
						</div>

						<!-- Actions -->
						<div class="flex shrink-0 gap-2">
							<button
								onclick={() => toggleFulfilled(order)}
								class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 {order.isFulfilled
									? 'bg-gray-200 hover:bg-gray-300'
									: 'bg-green-500 text-white hover:bg-green-600'}"
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
								onclick={() => (confirmModal = { type: 'soft-delete', order })}
								class="flex cursor-pointer items-center gap-1 rounded-full border-4 border-black px-3 py-2 font-bold transition-all duration-200 hover:border-dashed"
								title={$t.admin.softDelete}
							>
								<Trash2 size={16} />
							</button>
						</div>
					</div>
				</div>
			{/each}
		</div>
	{/if}

	<!-- Removed Orders Section -->
	{#if deletedOrders.length > 0}
		<div class="mt-12">
			<h2 class="mb-4 flex items-center gap-2 text-2xl font-bold text-gray-400">
				<Trash2 size={24} />
				{$t.admin.removed} ({deletedOrders.length})
			</h2>
			<div class="grid gap-4">
				{#each deletedOrders as order}
					<div class="rounded-2xl border-4 border-gray-300 bg-gray-50 p-4 opacity-60">
						<div class="flex items-start gap-4">
							<img
								src={order.itemImage}
								alt={order.itemName}
								class="h-16 w-16 shrink-0 rounded-lg border-2 border-gray-300 object-cover grayscale"
							/>

							<div class="min-w-0 flex-1">
								<div class="mb-1 flex items-center gap-2">
									<h3 class="text-lg font-bold text-gray-500">{order.itemName}</h3>
									<span class="text-gray-400">&times;{order.quantity}</span>
								</div>

								<div class="mb-2 flex flex-wrap items-center gap-2">
									<a href="/admin/users/{order.userId}" class="text-sm font-bold text-gray-500 hover:underline">
										@{order.username}
									</a>
									<span class="text-gray-300">&bull;</span>
									<span class="text-sm text-gray-400">{formatDate(order.createdAt)}</span>
									<span class="text-gray-300">&bull;</span>
									<span class="text-sm font-bold text-gray-500">{order.totalPrice} scraps</span>
								</div>
							</div>

							<div class="flex shrink-0 gap-2">
								<button
									onclick={() => restoreOrder(order)}
									class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
								>
									<RotateCcw size={16} />
									{$t.admin.restore}
								</button>
								<button
									onclick={() => (confirmModal = { type: 'permanent-delete', order })}
									class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-red-600 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed"
								>
									<Trash2 size={16} />
									{$t.admin.permanentDelete}
								</button>
							</div>
						</div>
					</div>
				{/each}
			</div>
		</div>
	{/if}
</div>

<!-- Confirmation Modal -->
{#if confirmModal}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (confirmModal = null)}
		onkeydown={(e) => e.key === 'Escape' && (confirmModal = null)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">
				{confirmModal.type === 'soft-delete' ? $t.admin.softDelete : $t.admin.permanentDelete}
			</h2>
			<p class="mb-6 text-gray-600">
				{confirmModal.type === 'soft-delete' ? $t.admin.confirmSoftDelete : $t.admin.confirmPermanentDelete}
			</p>
			<div class="flex gap-3">
				<button
					onclick={() => (confirmModal = null)}
					disabled={actionLoading}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				{#if confirmModal.type === 'soft-delete'}
					<button
						onclick={() => confirmModal && softDeleteOrder(confirmModal.order)}
						disabled={actionLoading}
						class="flex-1 cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
					>
						{actionLoading ? '...' : $t.admin.softDelete}
					</button>
				{:else}
					<button
						onclick={() => confirmModal && permanentDeleteOrder(confirmModal.order)}
						disabled={actionLoading}
						class="flex-1 cursor-pointer rounded-full border-4 border-red-600 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
					>
						{actionLoading ? '...' : $t.admin.permanentDelete}
					</button>
				{/if}
			</div>
		</div>
	</div>
{/if}
