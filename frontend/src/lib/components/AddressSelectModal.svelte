<script lang="ts">
	import { X } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';
	import { showToast } from '$lib/stores';
	import AccountAddressCard, { type AccountAddress } from './AccountAddressCard.svelte';
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

	let address = $state<AccountAddress | null>(null);
	let loaded = $state(false);
	let loading = $state(false);
	let error = $state<string | null>(null);

	let canSubmit = $derived(!!address?.complete);

	async function handleSubmit() {
		if (!canSubmit) return;

		loading = true;
		error = null;

		try {
			const response = await fetch(`${API_URL}/shop/orders/${orderId}/address`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({})
			});

			if (!response.ok) {
				const data = await response.json().catch(() => ({}));
				throw new Error(data.error || data.message || $t.address.failedToSaveAddress);
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
						.confirmItsRight}
				</p>
			</div>
		{/if}

		{#if error}
			<div class="mb-4 rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
				{error}
			</div>
		{/if}

		<AccountAddressCard bind:address bind:loaded />

		{#if loaded}
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
