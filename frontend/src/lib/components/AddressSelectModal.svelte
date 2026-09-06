<script lang="ts">
	import { ChevronDown, ExternalLink, X } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { onMount } from 'svelte';
	import { t } from '$lib/i18n';
	import { logout } from '$lib/auth-client';
	import { showToast } from '$lib/stores';

	interface Address {
		id: string;
		firstName: string;
		lastName: string;
		line1: string;
		line2: string | null;
		city: string;
		state: string;
		postalCode: string;
		country: string;
		phoneNumber: string | null;
		primary: boolean;
	}

	import type { Snippet } from 'svelte';

	let {
		orderId,
		itemName,
		onClose,
		onComplete,
		header
	}: {
		orderId: number;
		itemName: string;
		onClose: () => void;
		onComplete: () => void;
		header?: Snippet;
	} = $props();

	let addresses = $state<Address[]>([]);
	let selectedAddressId = $state<string | null>(null);
	let showDropdown = $state(false);
	let loading = $state(false);
	let loadingAddresses = $state(true);
	let error = $state<string | null>(null);

	let selectedAddress = $derived(addresses.find((a) => a.id === selectedAddressId));
	let canSubmit = $derived(selectedAddressId !== null);

	let formFirstName = $state('');
	let formLastName = $state('');
	let formLine1 = $state('');
	let formLine2 = $state('');
	let formCity = $state('');
	let formState = $state('');
	let formPostalCode = $state('');
	let formCountry = $state('');
	let formPhone = $state('');

	$effect(() => {
		const addr = selectedAddress;
		formFirstName = addr?.firstName || '';
		formLastName = addr?.lastName || '';
		formLine1 = addr?.line1 || '';
		formLine2 = addr?.line2 || '';
		formCity = addr?.city || '';
		formState = addr?.state || '';
		formPostalCode = addr?.postalCode || '';
		formCountry = addr?.country || '';
		formPhone = addr?.phoneNumber || '';
	});

	onMount(async () => {
		try {
			const response = await fetch(`${API_URL}/shop/addresses`, {
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				addresses = Array.isArray(data) ? data : [];
				const primary = addresses.find((a) => a.primary);
				if (primary) {
					selectedAddressId = primary.id;
				} else if (addresses.length === 1) {
					selectedAddressId = addresses[0].id;
				}
			}
		} catch (e) {
			console.error('Failed to fetch addresses:', e);
		} finally {
			loadingAddresses = false;
		}
	});

	function selectAddress(id: string) {
		selectedAddressId = id;
		showDropdown = false;
	}

	function fullName(addr: Address): string {
		return [addr.firstName, addr.lastName].filter(Boolean).join(' ');
	}

	function getSelectedAddressLabel(): string {
		const addr = addresses.find((a) => a.id === selectedAddressId);
		if (!addr) return $t.address.selectAnAddress;
		const name = fullName(addr);
		return name ? `${name}, ${addr.city}` : addr.city;
	}

	async function handleSubmit() {
		if (!canSubmit || !selectedAddress) return;

		loading = true;
		error = null;

		const shippingAddress = JSON.stringify({
			firstName: formFirstName,
			lastName: formLastName,
			address1: formLine1,
			address2: formLine2 || null,
			city: formCity,
			state: formState,
			postalCode: formPostalCode,
			country: formCountry,
			phone: formPhone || null
		});

		try {
			const response = await fetch(`${API_URL}/shop/orders/${orderId}/address`, {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				credentials: 'include',
				body: JSON.stringify({ shippingAddress })
			});

			if (!response.ok) {
				const data = await response.json().catch(() => ({}));
				throw new Error(data.message || $t.address.failedToSaveAddress);
			}

			showToast($t.address.orderConfirmedToast, 'success');
			onComplete();
			onClose();
		} catch (e) {
			error = e instanceof Error ? e.message : $t.address.failedToSaveAddress;
		} finally {
			loading = false;
		}
	}
</script>

<div
	class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
	role="dialog"
	tabindex="-1"
>
	<div
		class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border-4 border-black bg-white p-6"
	>
		<div class="mb-6 flex items-start justify-between gap-4">
			<h2 class="text-2xl font-bold">{$t.address.shippingAddress}</h2>
			<button
				type="button"
				onclick={onClose}
				aria-label="Close"
				class="flex h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded-full border-2 border-black transition-all hover:border-dashed"
			>
				<X size={16} />
			</button>
		</div>

		{#if header}
			{@render header()}
		{:else}
			<div class="mb-6 rounded-lg border-2 border-black bg-gray-50 p-4">
				<p class="text-lg font-bold">{$t.address.congratulations}</p>
				<p class="mt-1 text-gray-600">
					{$t.address.youWon} <span class="font-bold">{itemName}</span>! {$t.address
						.selectShippingAddress}
				</p>
			</div>
		{/if}

		{#if error}
			<div class="mb-4 rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
				{error}
			</div>
		{/if}

		<div class="space-y-4">
			{#if loadingAddresses}
				<div class="py-4 text-center text-gray-500">{$t.address.loadingAddresses}</div>
			{:else if addresses.length > 0}
				<div>
					<label class="mb-1 block text-sm font-bold">{$t.address.yourAddresses}</label>
					<div class="relative">
						<button
							type="button"
							onclick={() => (showDropdown = !showDropdown)}
							class="flex w-full cursor-pointer items-center justify-between rounded-lg border-2 border-black px-4 py-2 text-left focus:border-dashed focus:outline-none"
						>
							<span class={selectedAddressId ? '' : 'text-gray-500'}
								>{getSelectedAddressLabel()}</span
							>
							<ChevronDown
								size={20}
								class={showDropdown ? 'rotate-180 transition-transform' : 'transition-transform'}
							/>
						</button>

						{#if showDropdown}
							<div
								class="absolute top-full right-0 left-0 z-10 mt-1 max-h-48 overflow-y-auto rounded-lg border-2 border-black bg-white"
							>
								{#each addresses as addr}
									<button
										type="button"
										onclick={() => selectAddress(addr.id)}
										class="w-full cursor-pointer px-4 py-2 text-left hover:bg-gray-100 {addr.id ===
										selectedAddressId
											? 'bg-gray-100'
											: ''}"
									>
										<span class="font-medium"
											>{fullName(addr) || $t.address.unnamedAddress}
											{#if addr.primary}<span class="text-xs text-gray-500"
													>({$t.address.primary})</span
												>{/if}</span
										>
										<span class="block text-sm text-gray-500"
											>{[addr.line1, addr.city].filter(Boolean).join(', ')}</span
										>
									</button>
								{/each}
							</div>
						{/if}
					</div>
				</div>

				{#if selectedAddress && (!selectedAddress.firstName || !selectedAddress.lastName || !selectedAddress.phoneNumber)}
					<div class="rounded-lg border-2 border-dashed border-yellow-600 bg-yellow-50 p-3 text-sm">
						{$t.address.missingInfoNotice}
						<button
							type="button"
							onclick={() => logout()}
							class="cursor-pointer font-bold underline hover:no-underline"
						>
							{$t.address.reconnectHackClubAuth}
						</button>
					</div>
				{/if}

				{#if selectedAddress}
					<div class="rounded-lg border-2 border-black bg-gray-50 p-4">
						<p class="mb-3 text-sm font-bold">{$t.address.selectedAddress}</p>
						<div class="grid grid-cols-2 gap-2">
							<label class="text-xs font-bold text-gray-600">
								{$t.address.firstName}
								<input
									type="text"
									bind:value={formFirstName}
									class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
								/>
							</label>
							<label class="text-xs font-bold text-gray-600">
								{$t.address.lastName}
								<input
									type="text"
									bind:value={formLastName}
									class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
								/>
							</label>
						</div>
						<label class="mt-2 block text-xs font-bold text-gray-600">
							{$t.address.addressLine1}
							<input
								type="text"
								bind:value={formLine1}
								class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
							/>
						</label>
						<label class="mt-2 block text-xs font-bold text-gray-600">
							{$t.address.addressLine2}
							<input
								type="text"
								bind:value={formLine2}
								class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
							/>
						</label>
						<div class="mt-2 grid grid-cols-3 gap-2">
							<label class="text-xs font-bold text-gray-600">
								{$t.address.city}
								<input
									type="text"
									bind:value={formCity}
									class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
								/>
							</label>
							<label class="text-xs font-bold text-gray-600">
								{$t.address.state}
								<input
									type="text"
									bind:value={formState}
									class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
								/>
							</label>
							<label class="text-xs font-bold text-gray-600">
								{$t.address.postalCode}
								<input
									type="text"
									bind:value={formPostalCode}
									class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
								/>
							</label>
						</div>
						<label class="mt-2 block text-xs font-bold text-gray-600">
							{$t.address.country}
							<input
								type="text"
								bind:value={formCountry}
								class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
							/>
						</label>
						<label class="mt-2 block text-xs font-bold text-gray-600">
							{$t.address.phone}
							<input
								type="tel"
								bind:value={formPhone}
								class="mt-1 w-full rounded-lg border-2 border-black px-2 py-1 text-sm"
							/>
						</label>
					</div>
				{/if}

				<a
					href="https://auth.hackclub.com"
					target="_blank"
					rel="noopener noreferrer"
					class="inline-flex items-center gap-1 text-sm text-gray-500 transition-colors hover:text-black"
				>
					<ExternalLink size={14} />
					{$t.address.manageAddresses}
				</a>
			{:else}
				<div class="py-6 text-center">
					<p class="mb-4 text-gray-600">{$t.address.noSavedAddresses}</p>
					<a
						href="https://auth.hackclub.com"
						target="_blank"
						rel="noopener noreferrer"
						class="inline-flex cursor-pointer items-center gap-2 rounded-full bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800"
					>
						<ExternalLink size={16} />
						{$t.address.addAddress}
					</a>
					<p class="mt-4 text-sm text-gray-500">
						{$t.address.afterAddingAddress}
					</p>
				</div>
			{/if}
		</div>

		{#if addresses.length > 0}
			<div class="mt-6">
				<button
					onclick={handleSubmit}
					disabled={loading || !canSubmit}
					class="w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
				>
					{loading ? $t.common.saving : $t.address.confirmShippingAddress}
				</button>
			</div>
		{/if}
	</div>
</div>
