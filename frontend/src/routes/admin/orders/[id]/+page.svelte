<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import {
		Check,
		X,
		Package,
		Clock,
		Truck,
		CheckCircle,
		XCircle,
		Trash2,
		ArrowLeft,
		ShieldAlert,
		Mail
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

	async function copyField(value: string) {
		await navigator.clipboard.writeText(value);
		showToast('Copied!', 'success');
	}

	interface User {
		id: number;
		role: string;
	}

	let orderId = $derived($page.params.id);
	let user = $state<User | null>(null);
	let order = $state<Order | null>(null);
	let loading = $state(true);
	let notFound = $state(false);
	let actionLoading = $state(false);
	let trackingInput = $state('');
	let notesInput = $state('');
	let notesLoading = $state(false);
	let userNoteInput = $state('');
	let userNoteLoading = $state(false);
	let confirmDelete = $state(false);
	let confirmReason = $state('');

	onMount(async () => {
		user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}
		await fetchOrder();
	});

	async function fetchOrder() {
		loading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${orderId}`, {
				credentials: 'include'
			});
			if (response.ok) {
				order = await response.json();
				notesInput = order?.internalNotes ?? '';
				userNoteInput = order?.userNote ?? '';
				trackingInput = order?.trackingNumber ?? '';
			} else if (response.status === 404) {
				notFound = true;
			}
		} catch (_e) {
			showToast('failed to load order', 'error');
		} finally {
			loading = false;
		}
	}

	async function toggleFulfilled() {
		if (!order) return;
		actionLoading = true;
		try {
			const patchBody: Record<string, unknown> = { isFulfilled: !order.isFulfilled };
			if (!order.isFulfilled) {
				patchBody.trackingNumber = trackingInput.trim() || null;
			}
			const response = await fetch(`${API_URL}/admin/orders/${order.id}`, {
				method: 'PATCH',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify(patchBody)
			});
			if (response.ok) {
				const wasFulfilled = order.isFulfilled;
				order.isFulfilled = !wasFulfilled;
				if (!wasFulfilled) order.trackingNumber = trackingInput.trim() || null;
				showToast(wasFulfilled ? 'order marked as unfulfilled' : 'order marked as fulfilled', 'success');
			} else {
				const data = await response.json().catch(() => ({}));
				showToast(data.error || 'failed to update order', 'error');
			}
		} catch (_e) {
			showToast('failed to update order', 'error');
		} finally {
			actionLoading = false;
		}
	}

	async function saveOrderNotes() {
		if (!order) return;
		notesLoading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}/notes`, {
				method: 'PATCH',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ internalNotes: notesInput })
			});
			const data = await response.json().catch(() => ({}));
			if (response.ok) {
				order.internalNotes = notesInput;
				showToast('note saved', 'success');
			} else {
				showToast(data.error || 'failed to save note', 'error');
			}
		} catch (_e) {
			showToast('failed to save note', 'error');
		} finally {
			notesLoading = false;
		}
	}

	async function saveUserNote() {
		if (!order) return;
		userNoteLoading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}`, {
				method: 'PATCH',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ userNote: userNoteInput })
			});
			const data = await response.json().catch(() => ({}));
			if (response.ok) {
				order.userNote = userNoteInput;
				showToast('note saved — will be sent via Slack DM when the order is fulfilled', 'success');
			} else {
				showToast(data.error || 'failed to save note', 'error');
			}
		} catch (_e) {
			showToast('failed to save note', 'error');
		} finally {
			userNoteLoading = false;
		}
	}

	async function deleteOrder() {
		if (!order) return;
		actionLoading = true;
		try {
			const response = await fetch(`${API_URL}/admin/orders/${order.id}`, {
				method: 'DELETE',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({ reason: confirmReason })
			});
			const text = await response.text();
			let json: Record<string, string> | null = null;
			try {
				json = JSON.parse(text);
			} catch {
				// ignore parse error
			}
			if (response.ok) {
				showToast('order deleted', 'success');
				goto('/admin/orders');
			} else {
				const err = (json && (json.error || json.message)) || text || 'failed to delete';
				showToast(err, 'error');
			}
		} catch (_e) {
			showToast('failed to delete order', 'error');
		} finally {
			actionLoading = false;
			confirmDelete = false;
			confirmReason = '';
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
	<title>order #{orderId} - {$t.nav.admin} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-3xl px-6 pt-24 pb-24 md:px-12">
	<a href="/admin/orders" class="mb-6 inline-flex items-center gap-2 font-bold text-gray-500 hover:underline">
		<ArrowLeft size={18} />
		back to orders
	</a>

	{#if loading}
		<div class="py-12 text-center text-gray-500">{$t.common.loading}</div>
	{:else if notFound || !order}
		<div class="py-12 text-center text-gray-500">order not found</div>
	{:else}
		{@const StatusIcon = getStatusIcon(order.status)}
		<div
			class="overflow-hidden rounded-3xl border-4 {order.hackatimeBanned
				? 'border-red-500 bg-red-50'
				: 'border-black bg-white'} shadow-[8px_8px_0px_0px_rgba(0,0,0,1)]"
		>
			<div class="flex flex-wrap items-center gap-4 p-6">
				<img
					src={order.itemImage}
					alt={order.itemName}
					class="h-16 w-16 shrink-0 rounded-lg border-2 border-black object-cover"
				/>
				<div class="min-w-0 flex-1">
					<h1 class="text-2xl font-bold md:text-3xl">{order.itemName}</h1>
					<div class="flex flex-wrap items-center gap-2 text-sm text-gray-600">
						<a href="/admin/users/{order.userId}" class="font-bold hover:underline">@{order.username}</a>
						<span class="text-gray-400">•</span>
						<span>{formatDate(order.createdAt)}</span>
						<span class="text-gray-400">•</span>
						<span class="font-bold">{order.totalPrice} scraps</span>
						{#if order.quantity > 1}
							<span class="text-gray-400">•</span>
							<span class="font-bold text-gray-500">×{order.quantity}</span>
						{/if}
					</div>
				</div>
				<div class="flex shrink-0 flex-wrap items-center gap-2">
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
					{#if order.hackatimeBanned}
						<span
							class="inline-flex items-center gap-1 rounded-full border-2 border-red-600 bg-red-100 px-2 py-0.5 text-xs font-bold text-red-700"
						>
							<ShieldAlert size={12} />
							ht banned
						</span>
					{/if}
				</div>
			</div>

			<div class="border-t-4 border-dashed border-gray-200 p-6">
				{#if order.hackatimeBanned}
					<p class="mb-4 rounded-xl border-2 border-red-500 bg-red-100 p-3 text-sm font-bold text-red-700">
						this user is hackatime banned — do not fulfill
					</p>
				{/if}

				<div class="flex flex-col gap-6 md:flex-row md:items-start md:justify-between">
					<div class="min-w-0 flex-1 text-sm">
						{#if order.notes}
							<p class="mb-3 text-gray-600"><strong>Notes:</strong> {order.notes}</p>
						{/if}

						{#if parseShippingAddress(order.shippingAddress)}
							{@const addr = parseShippingAddress(order.shippingAddress)!}
							<div class="group/addr rounded-xl border-2 border-gray-300 bg-white p-4">
								<p class="mb-2 text-xs font-bold text-gray-500 uppercase">shipping address</p>
								<div
									class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 blur-sm transition-all duration-300 select-none group-hover/addr:blur-none group-hover/addr:select-auto"
								>
									<span class="font-bold text-gray-500">name</span>
									<span class="cursor-pointer hover:underline" onclick={() => copyField(formatName(addr))}>{formatName(addr)}</span>
									<span class="font-bold text-gray-500">address 1</span>
									<span class="cursor-pointer hover:underline" onclick={() => copyField(addr.address1)}>{addr.address1}</span>
									{#if addr.address2}
										<span class="font-bold text-gray-500">address 2</span>
										<span class="cursor-pointer hover:underline" onclick={() => copyField(addr.address2!)}>{addr.address2}</span>
									{/if}
									<span class="font-bold text-gray-500">city</span>
									<span class="cursor-pointer hover:underline" onclick={() => copyField(addr.city)}>{addr.city}</span>
									<span class="font-bold text-gray-500">state</span>
									<span class="cursor-pointer hover:underline" onclick={() => copyField(addr.state)}>{addr.state}</span>
									<span class="font-bold text-gray-500">zip</span>
									<span class="cursor-pointer hover:underline" onclick={() => copyField(addr.postalCode)}>{addr.postalCode}</span>
									<span class="font-bold text-gray-500">country</span>
									<span class="cursor-pointer hover:underline" onclick={() => copyField(addr.country)}>{addr.country}</span>
									{#if order.phone || addr.phone}
										<span class="font-bold text-gray-500">phone</span>
										<span class="cursor-pointer hover:underline" onclick={() => copyField((order.phone || addr.phone)!)}>{order.phone || addr.phone}</span>
									{/if}
									{#if order.email}
										<span class="font-bold text-gray-500">email</span>
										<span class="cursor-pointer hover:underline" onclick={() => copyField(order.email!)}>{order.email}</span>
									{/if}
								</div>
							</div>
						{:else if order.orderType === 'win'}
							<div class="rounded-xl border-2 border-yellow-300 bg-yellow-100 p-4">
								<p class="font-bold text-yellow-700">no shipping address provided</p>
							</div>
						{/if}
						{#if (order.phone || order.email) && !parseShippingAddress(order.shippingAddress)}
							<div class="mt-2 rounded-xl border-2 border-gray-300 bg-white p-4">
								<div class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
									{#if order.phone}
										<span class="font-bold text-gray-500">phone</span>
										<span class="cursor-pointer hover:underline" onclick={() => copyField(order.phone!)}>{order.phone}</span>
									{/if}
									{#if order.email}
										<span class="font-bold text-gray-500">email</span>
										<span class="cursor-pointer hover:underline" onclick={() => copyField(order.email!)}>{order.email}</span>
									{/if}
								</div>
							</div>
						{/if}

						<div class="mt-2 rounded-xl border-2 border-gray-300 bg-white p-4">
							<p class="mb-2 text-xs font-bold text-gray-500 uppercase">internal notes (admins only)</p>
							<textarea
								bind:value={notesInput}
								placeholder="anything weird about this order? leave a note for other admins"
								rows="2"
								class="w-full rounded-lg border-2 border-black px-3 py-2 text-sm transition-all duration-200 placeholder:text-gray-400 focus:border-dashed focus:outline-none"
							></textarea>
							<button
								onclick={saveOrderNotes}
								disabled={notesLoading}
								class="mt-2 cursor-pointer rounded-full border-2 border-black px-3 py-1 text-xs font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
							>
								{notesLoading ? 'saving...' : 'save note'}
							</button>
						</div>

						<div class="mt-2 rounded-xl border-2 border-gray-300 bg-white p-4">
							<p class="mb-2 text-xs font-bold text-gray-500 uppercase">note to user (sent via slack dm once fulfilled)</p>
							{#if order.slackId}
								<textarea
									bind:value={userNoteInput}
									placeholder="e.g. sorry for the wait! sizing ran small so we bumped you up a size"
									rows="2"
									class="w-full rounded-lg border-2 border-black px-3 py-2 text-sm transition-all duration-200 placeholder:text-gray-400 focus:border-dashed focus:outline-none"
								></textarea>
								<button
									onclick={saveUserNote}
									disabled={userNoteLoading}
									class="mt-2 flex cursor-pointer items-center gap-1 rounded-full border-2 border-black px-3 py-1 text-xs font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
								>
									<Mail size={12} />
									{userNoteLoading ? 'saving...' : 'save note'}
								</button>
							{:else}
								<p class="text-xs text-gray-400">no slack account linked for this user</p>
							{/if}
						</div>
					</div>

					<!-- Actions -->
					<div class="flex shrink-0 flex-col gap-3 md:w-48">
						{#if !order.isFulfilled}
							<input
								type="text"
								placeholder="tracking # (optional)"
								bind:value={trackingInput}
								class="w-full rounded-lg border-2 border-black px-3 py-2 text-sm font-bold transition-all duration-200 placeholder:text-gray-400 focus:border-dashed focus:outline-none"
							/>
						{:else if order.trackingNumber}
							<div class="rounded-lg border-2 border-gray-300 bg-gray-50 px-3 py-2 text-sm">
								<p class="text-xs font-bold text-gray-500 uppercase">tracking</p>
								<p class="font-bold break-all">
									{#if order.trackingNumber.startsWith('ltr!')}
										<a
											href="https://mail.hackclub.com/back_office/letters/{order.trackingNumber}"
											target="_blank"
											rel="noopener noreferrer"
											class="text-blue-600 hover:underline"
										>
											{order.trackingNumber}
										</a>
									{:else}
										{order.trackingNumber}
									{/if}
								</p>
							</div>
						{/if}
						<button
							onclick={toggleFulfilled}
							disabled={actionLoading}
							class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 disabled:cursor-not-allowed disabled:opacity-50 {order.isFulfilled
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
							onclick={() => (confirmDelete = true)}
							class="flex w-full cursor-pointer items-center justify-center gap-1 rounded-full border-4 border-red-600 px-3 py-2 font-bold text-red-600 transition-all duration-200 hover:border-dashed"
							title="delete order"
						>
							<Trash2 size={16} />
							delete order
						</button>
					</div>
				</div>
			</div>
		</div>
	{/if}
</div>

<!-- Delete Confirmation Modal -->
{#if confirmDelete && order}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && (confirmDelete = false)}
		onkeydown={(e) => e.key === 'Escape' && (confirmDelete = false)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">delete order</h2>
			<p class="mb-2 text-gray-600">
				this will permanently delete the order for <span class="font-bold">@{order.username}</span>
				and remove associated refinery/roll/penalty records from their financial timeline. No refund
				or bonus will be issued.
			</p>
			<p class="mb-6 text-sm font-bold text-red-600">this action is destructive and cannot be undone from here.</p>
			<label for="confirm-reason" class="mb-2 block text-sm font-bold text-gray-700">reason (min 3 chars)</label>
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
				<p id="confirm-reason-error" class="mb-4 text-sm text-red-600">reason must be at least 3 characters</p>
			{:else}
				<div class="mb-4" aria-hidden="true"></div>
			{/if}
			<div class="flex gap-3">
				<button
					onclick={() => ((confirmDelete = false), (confirmReason = ''))}
					disabled={actionLoading}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={() => {
						if (!confirmReason || confirmReason.trim().length < 3) return;
						deleteOrder();
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
