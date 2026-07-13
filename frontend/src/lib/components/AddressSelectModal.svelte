<script lang="ts">
	import { ChevronDown, ExternalLink } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { onMount } from 'svelte';
	import { t } from '$lib/i18n';

	interface Address {
		id: string;
		first_name: string;
		last_name: string;
		line_1: string;
		line_2: string | null;
		city: string;
		state: string;
		postal_code: string;
		country: string;
		phone_number: string | null;
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

	function getSelectedAddressLabel(): string {
		const addr = addresses.find((a) => a.id === selectedAddressId);
		if (addr) return `${addr.first_name} ${addr.last_name}, ${addr.city}`;
		return $t.address.selectAnAddress;
	}

	async function handleSubmit() {
		if (!canSubmit || !selectedAddress) return;

		loading = true;
		error = null;

		const shippingAddress = JSON.stringify({
			firstName: selectedAddress.first_name,
			lastName: selectedAddress.last_name,
			address1: selectedAddress.line_1,
			address2: selectedAddress.line_2 || null,
			city: selectedAddress.city,
			state: selectedAddress.state,
			postalCode: selectedAddress.postal_code,
			country: selectedAddress.country,
			phone: selectedAddress.phone_number || null
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
		<div class="mb-6">
			<h2 class="text-2xl font-bold">{$t.address.shippingAddress}</h2>
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
											>{addr.first_name}
											{addr.last_name}
											{#if addr.primary}<span class="text-xs text-gray-500"
													>({$t.address.primary})</span
												>{/if}</span
										>
										<span class="block text-sm text-gray-500">{addr.line_1}, {addr.city}</span>
									</button>
								{/each}
							</div>
						{/if}
					</div>
				</div>

				{#if selectedAddress}
					<div class="rounded-lg border-2 border-black bg-gray-50 p-4">
						<p class="mb-2 text-sm font-bold">{$t.address.selectedAddress}</p>
						<p class="text-sm">{selectedAddress.first_name} {selectedAddress.last_name}</p>
						<p class="text-sm">{selectedAddress.line_1}</p>
						{#if selectedAddress.line_2}
							<p class="text-sm">{selectedAddress.line_2}</p>
						{/if}
						<p class="text-sm">
							{selectedAddress.city}, {selectedAddress.state}
							{selectedAddress.postal_code}
						</p>
						<p class="text-sm">{selectedAddress.country}</p>
						{#if selectedAddress.phone_number}
							<p class="mt-1 text-sm text-gray-500">📞 {selectedAddress.phone_number}</p>
						{/if}
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
