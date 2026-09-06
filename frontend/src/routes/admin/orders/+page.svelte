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
		Search,
		ShieldAlert
	} from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { showToast } from '$lib/stores';
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
		internalNotes: string | null;
		userNote: string | null;
		trackingNumber: string | null;
		isFulfilled: boolean;
		shippingAddress: string | null;
		phone: string | null;
		email: string | null;
		createdAt: string;
		itemId: number;
		itemName: string;
		itemImage: string;
		userId: number;
		username: string;
		userAvatar: string | null;
		slackId: string | null;
		hackatimeBanned: boolean;
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
	let filterItem = $state('');
	let filterUser = $state('');
	let filterRegion = $state<'' | 'us' | 'intl'>('');
	let hideConsolations = $state(false);

	let uniqueItems = $derived(
		[...new Map(orders.map((o) => [o.itemName, o.itemName])).values()].sort()
	);
	let uniqueUsers = $derived(
		[...new Map(orders.map((o) => [o.userId, o.username])).values()].sort()
	);

	let filteredOrders = $derived.by(() => {
		let result =
			filter === 'all'
				? orders
				: filter === 'pending'
					? orders.filter((o) => !o.isFulfilled)
					: orders.filter((o) => o.isFulfilled);

		if (filterItem) {
			result = result.filter((o) => o.itemName === filterItem);
		}

		if (filterUser) {
			result = result.filter((o) => o.username === filterUser);
		}

		if (filterRegion) {
			result = result.filter((o) => {
				const addr = parseShippingAddress(o.shippingAddress);
				const country = addr?.country?.toLowerCase().trim() ?? '';
				const isUS =
					country === 'us' ||
					country === 'usa' ||
					country === 'united states' ||
					country === 'united states of america';
				return filterRegion === 'us' ? isUS : !isUS;
			});
		}

		if (searchQuery.trim()) {
			const q = searchQuery.trim().toLowerCase();
			result = result.filter((o) => {
				if (String(o.id).includes(q)) return true;
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

		if (hideConsolations) {
			result = result.filter((o) => o.orderType !== 'consolation');
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

		return [...result].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
	});

	let mainOrders = $derived(filteredOrders.filter((o) => !o.hackatimeBanned));
	let bannedOrders = $derived(filteredOrders.filter((o) => o.hackatimeBanned));

	onMount(async () => {
		user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'creator')) {
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
		} catch (_e) {
			showToast('failed to load orders', 'error');
		} finally {
			loading = false;
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

<div class="mx-auto max-w-5xl px-6 pt-24 pb-24 md:px-12">
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
					placeholder="search by order #, name, or slack id..."
					bind:value={searchQuery}
					class="w-full rounded-full border-4 border-black py-2 pr-4 pl-10 font-bold transition-all duration-200 placeholder:text-gray-400 focus:border-dashed focus:ring-0 focus:outline-none"
				/>
			</div>
			<div class="flex flex-col">
				<label for="filter-item" class="mb-1 text-xs font-bold text-gray-500 uppercase">item</label>
				<select
					id="filter-item"
					bind:value={filterItem}
					class="cursor-pointer rounded-xl border-4 border-black px-3 py-2 font-bold transition-all duration-200 focus:border-dashed focus:outline-none {filterItem
						? 'bg-black text-white'
						: ''}"
				>
					<option value="">all items</option>
					{#each uniqueItems as item}
						<option value={item}>{item}</option>
					{/each}
				</select>
			</div>
			<div class="flex flex-col">
				<label for="filter-user" class="mb-1 text-xs font-bold text-gray-500 uppercase">user</label>
				<select
					id="filter-user"
					bind:value={filterUser}
					class="cursor-pointer rounded-xl border-4 border-black px-3 py-2 font-bold transition-all duration-200 focus:border-dashed focus:outline-none {filterUser
						? 'bg-black text-white'
						: ''}"
				>
					<option value="">all users</option>
					{#each uniqueUsers as username}
						<option value={username}>@{username}</option>
					{/each}
				</select>
			</div>
			<div class="flex flex-col">
				<label for="filter-region" class="mb-1 text-xs font-bold text-gray-500 uppercase"
					>region</label
				>
				<select
					id="filter-region"
					bind:value={filterRegion}
					class="cursor-pointer rounded-xl border-4 border-black px-3 py-2 font-bold transition-all duration-200 focus:border-dashed focus:outline-none {filterRegion
						? 'bg-black text-white'
						: ''}"
				>
					<option value="">all regions</option>
					<option value="us">US only</option>
					<option value="intl">non-US</option>
				</select>
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
				<button
				onclick={() => (hideConsolations = !hideConsolations)}
				class="cursor-pointer rounded-xl border-4 border-black px-3 py-2 font-bold transition-all duration-200 {hideConsolations
					? 'bg-black text-white'
					: 'hover:border-dashed'}"
			>
				hide consolations
			</button>
			{#if dateFrom || dateTo || filterItem || filterUser || filterRegion || hideConsolations}
					<button
						onclick={() => {
							dateFrom = '';
							dateTo = '';
							filterItem = '';
							filterUser = '';
							filterRegion = '';
							hideConsolations = false;
						}}
						class="cursor-pointer rounded-xl border-4 border-black px-3 py-2 font-bold transition-all duration-200 hover:border-dashed"
						title="clear filters"
					>
						<X size={18} />
					</button>
				{/if}
			</div>
		</div>
	</div>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if mainOrders.length === 0 && bannedOrders.length === 0}
		<div class="py-12 text-center text-gray-500">no orders found</div>
	{:else}
		<div class="flex flex-col gap-3">
			{#each mainOrders as order}
				{@const StatusIcon = getStatusIcon(order.status)}
				<button
					onclick={() => goto(`/admin/orders/${order.id}`)}
					class="flex w-full cursor-pointer items-center gap-4 rounded-2xl border-4 border-black p-4 text-left transition-colors hover:bg-black/5 {order.isFulfilled
						? 'bg-green-50'
						: 'bg-white'}"
				>
					<img
						src={order.itemImage}
						alt={order.itemName}
						class="h-14 w-14 shrink-0 rounded-lg border-2 border-black object-cover"
					/>

					<div class="min-w-0 flex-1">
						<p class="truncate text-lg font-bold">{order.itemName}</p>
						<div class="flex items-center gap-1.5 text-sm text-gray-500">
							{#if order.userAvatar}
								<img src={order.userAvatar} alt="" class="h-5 w-5 rounded-full object-cover" />
							{:else}
								<div
									class="flex h-5 w-5 items-center justify-center rounded-full bg-gray-200 text-[10px] font-bold text-gray-500"
								>
									{order.username[0]?.toUpperCase()}
								</div>
							{/if}
							<a
								href="/admin/users/{order.userId}"
								onclick={(e) => e.stopPropagation()}
								class="truncate hover:text-black hover:underline"
							>
								@{order.username}
							</a>
						</div>
					</div>

					<div class="flex shrink-0 flex-col items-end gap-1.5">
						<div class="flex items-center gap-2">
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
						<span class="text-xs text-gray-400">order #{order.id} • {formatDate(order.createdAt)}</span>
					</div>
				</button>
			{/each}
		</div>

		{#if bannedOrders.length > 0}
			<div class="mt-12">
				<div class="mb-4 flex items-center gap-3">
					<ShieldAlert size={24} class="text-red-600" />
					<h2 class="text-2xl font-bold text-red-700">hackatime banned orders</h2>
					<span class="rounded-full border-2 border-red-600 bg-red-100 px-3 py-0.5 text-sm font-bold text-red-700">
						{bannedOrders.length}
					</span>
				</div>
				<p class="mb-6 text-sm text-gray-500">these orders belong to users who are banned on hackatime — do not fulfill</p>
				<div class="flex flex-col gap-3">
					{#each bannedOrders as order}
						<button
							onclick={() => goto(`/admin/orders/${order.id}`)}
							class="flex w-full cursor-pointer items-center gap-4 rounded-2xl border-4 border-red-400 bg-red-50 p-4 text-left hover:bg-red-100"
						>
							<img
								src={order.itemImage}
								alt={order.itemName}
								class="h-14 w-14 shrink-0 rounded-lg border-2 border-red-400 object-cover"
							/>

							<div class="min-w-0 flex-1">
								<p class="truncate text-lg font-bold text-red-800">{order.itemName}</p>
								<div class="flex items-center gap-1.5 text-sm text-red-500">
									{#if order.userAvatar}
										<img src={order.userAvatar} alt="" class="h-5 w-5 rounded-full object-cover" />
									{:else}
										<div
											class="flex h-5 w-5 items-center justify-center rounded-full bg-red-200 text-[10px] font-bold text-red-600"
										>
											{order.username[0]?.toUpperCase()}
										</div>
									{/if}
									<a
										href="/admin/users/{order.userId}"
										onclick={(e) => e.stopPropagation()}
										class="truncate hover:text-red-900 hover:underline"
									>
										@{order.username}
									</a>
								</div>
							</div>

							<div class="flex shrink-0 flex-col items-end gap-1.5">
								<span
									class="inline-flex items-center gap-1 rounded-full border-2 border-red-600 bg-red-100 px-2 py-0.5 text-xs font-bold text-red-700"
								>
									<ShieldAlert size={12} />
									ht banned
								</span>
								<span class="text-xs text-red-400">order #{order.id} • {formatDate(order.createdAt)}</span>
							</div>
						</button>
					{/each}
				</div>
			</div>
		{/if}
	{/if}
</div>

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
