<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		ArrowLeft,
		Package,
		CheckCircle,
		Clock,
		Truck,
		MapPin,
		Origami,
		Spool
	} from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { getUser } from '$lib/auth-client';
	import { t } from '$lib/i18n';

	interface Order {
		id: number;
		quantity: number;
		pricePerItem: number;
		totalPrice: number;
		status: string;
		orderType: string;
		shippingAddress: string | null;
		trackingNumber: string | null;
		isFulfilled: boolean;
		createdAt: string;
		itemId: number;
		itemName: string;
		itemImage: string;
	}

	let orders = $state<Order[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);

	onMount(async () => {
		const user = await getUser();
		if (!user) {
			goto('/');
			return;
		}

		try {
			const response = await fetch(`${API_URL}/shop/orders`, {
				credentials: 'include'
			});

			if (!response.ok) {
				throw new Error('Failed to fetch orders');
			}

			const data = await response.json();
			if (data.error) {
				throw new Error(data.error);
			}

			orders = data;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load orders';
		} finally {
			loading = false;
		}
	});

	function formatDate(dateString: string): string {
		return new Date(dateString).toLocaleDateString('en-US', {
			year: 'numeric',
			month: 'short',
			day: 'numeric',
			hour: '2-digit',
			minute: '2-digit'
		});
	}

	function getOrderTypeLabel(orderType: string): string {
		switch (orderType) {
			case 'luck_win':
				return $t.orders.won;
			case 'consolation':
				return $t.orders.consolation;
			case 'purchase':
				return $t.orders.purchased;
			default:
				return orderType;
		}
	}

	function getStatusColor(status: string, isFulfilled: boolean): string {
		if (isFulfilled) return 'bg-green-100 text-green-700 border-green-600';
		switch (status) {
			case 'pending':
				return 'bg-yellow-100 text-yellow-700 border-yellow-600';
			case 'shipped':
				return 'bg-blue-100 text-blue-700 border-blue-600';
			case 'delivered':
				return 'bg-green-100 text-green-700 border-green-600';
			default:
				return 'bg-gray-100 text-gray-700 border-gray-600';
		}
	}

	function getStatusIcon(status: string, isFulfilled: boolean) {
		if (isFulfilled) return CheckCircle;
		switch (status) {
			case 'shipped':
				return Truck;
			case 'delivered':
				return CheckCircle;
			default:
				return Clock;
		}
	}

	function getStatusLabel(status: string, isFulfilled: boolean): string {
		if (isFulfilled) return $t.orders.fulfilled;
		switch (status) {
			case 'pending':
				return $t.orders.pending;
			case 'shipped':
				return $t.orders.shipped;
			case 'delivered':
				return $t.orders.delivered;
			default:
				return status;
		}
	}

	interface ParsedAddress {
		firstName?: string;
		lastName?: string;
		address1?: string;
		address2?: string | null;
		city?: string;
		state?: string;
		postalCode?: string;
		country?: string;
		phone?: string;
	}

	function parseAddress(addressJson: string): ParsedAddress | null {
		try {
			return JSON.parse(addressJson);
		} catch {
			return null;
		}
	}

	function formatAddress(addressJson: string): string {
		const addr = parseAddress(addressJson);
		if (!addr) return addressJson;

		const parts: string[] = [];
		if (addr.firstName || addr.lastName) {
			parts.push([addr.firstName, addr.lastName].filter(Boolean).join(' '));
		}
		if (addr.address1) parts.push(addr.address1);
		if (addr.address2) parts.push(addr.address2);
		if (addr.city || addr.state || addr.postalCode) {
			const cityLine = [addr.city, addr.state].filter(Boolean).join(', ');
			parts.push([cityLine, addr.postalCode].filter(Boolean).join(' '));
		}
		if (addr.country) parts.push(addr.country);

		return parts.join(', ');
	}
</script>

<svelte:head>
	<title>{$t.orders.myOrders} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<a
		href="/shop"
		class="mb-8 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
	>
		<ArrowLeft size={20} />
		{$t.orders.backToShop}
	</a>

	<h1 class="mb-8 text-4xl font-bold md:text-5xl">{$t.orders.myOrders}</h1>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.orders.loadingOrders}</div>
	{:else if error}
		<div class="py-12 text-center text-red-600">{error}</div>
	{:else if orders.length === 0}
		<div class="rounded-2xl border-4 border-dashed border-gray-300 p-12 text-center">
			<Package size={48} class="mx-auto mb-4 text-gray-400" />
			<p class="text-lg text-gray-500">{$t.orders.noOrdersYet}</p>
			<p class="mt-2 text-sm text-gray-400">{$t.orders.tryYourLuck}</p>
			<a
				href="/shop"
				class="mt-6 inline-block cursor-pointer rounded-full bg-black px-6 py-3 font-bold text-white transition-all duration-200 hover:bg-gray-800"
			>
				{$t.orders.goToShop}
			</a>
		</div>
	{:else}
		<div class="space-y-4">
			{#each orders as order}
				{@const StatusIcon = getStatusIcon(order.status, order.isFulfilled)}
				{@const isConsolation = order.orderType === 'consolation'}
				<div
					class="rounded-2xl border-4 border-black p-6 transition-all duration-200 hover:border-dashed"
				>
					<div class="flex gap-4">
						{#if isConsolation}
							<div
								class="flex h-20 w-20 shrink-0 items-center justify-center rounded-lg border-2 border-black bg-yellow-50"
							>
								<Origami size={40} class="text-yellow-600" />
							</div>
						{:else}
							<img
								src={order.itemImage}
								alt={order.itemName}
								class="h-20 w-20 shrink-0 rounded-lg border-2 border-black bg-gray-50 object-contain"
							/>
						{/if}
						<div class="min-w-0 flex-1">
							<div class="flex items-start justify-between gap-4">
								<div>
									{#if isConsolation}
										<h3 class="text-xl font-bold">{$t.orders.paperScraps}</h3>
										<p class="text-sm text-gray-400 line-through">{order.itemName}</p>
									{:else}
										<h3 class="text-xl font-bold">{order.itemName}</h3>
									{/if}
									<p class="text-sm text-gray-500">
										{getOrderTypeLabel(order.orderType)} · {formatDate(order.createdAt)}
									</p>
								</div>
								<span
									class="flex shrink-0 items-center gap-1 rounded-full border-2 px-3 py-1 text-sm font-bold {getStatusColor(
										order.status,
										order.isFulfilled
									)}"
								>
									<StatusIcon size={14} />
									{getStatusLabel(order.status, order.isFulfilled)}
								</span>
							</div>

							<div class="mt-3 flex flex-wrap gap-4 text-sm">
								<span class="flex items-center gap-1 font-bold text-gray-600">
									<Spool size={16} />
									{order.totalPrice}
								</span>
								{#if order.quantity > 1}
									<span class="text-gray-600">{$t.orders.qty}: {order.quantity}</span>
								{/if}
							</div>

							{#if order.shippingAddress}
								<div class="mt-3 flex items-start gap-2 text-sm text-gray-600">
									<MapPin size={16} class="mt-0.5 shrink-0" />
									<span class="wrap-break-word">{formatAddress(order.shippingAddress)}</span>
								</div>
							{:else if !order.isFulfilled}
								<p class="mt-3 text-sm font-bold text-yellow-600">
									{$t.orders.noShippingAddress}
								</p>
							{/if}

							{#if order.trackingNumber}
								<div class="mt-3 flex items-start gap-2 text-sm text-gray-600">
									<Truck size={16} class="mt-0.5 shrink-0" />
									<span class="font-bold">tracking: {order.trackingNumber}</span>
								</div>
							{/if}
						</div>
					</div>
				</div>
			{/each}
		</div>
	{/if}
</div>
