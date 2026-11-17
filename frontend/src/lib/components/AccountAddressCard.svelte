<script lang="ts" module>
	export interface AccountAddress {
		id: string;
		firstName: string | null;
		lastName: string | null;
		line1: string | null;
		line2: string | null;
		city: string | null;
		state: string | null;
		postalCode: string | null;
		country: string | null;
		phoneNumber: string | null;
		primary: boolean;
		complete: boolean;
	}
</script>

<script lang="ts">
	import { ExternalLink, RefreshCw } from '@lucide/svelte';
	import { onMount } from 'svelte';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';
	import { showToast } from '$lib/stores';

	const AUTH_URL = 'https://auth.hackclub.com';

	let {
		address = $bindable(null),
		loaded = $bindable(false)
	}: { address?: AccountAddress | null; loaded?: boolean } = $props();

	let resyncing = $state(false);
	let error = $state<string | null>(null);

	function apply(data: unknown) {
		const list = Array.isArray(data) ? (data as AccountAddress[]) : [];
		address = list[0] ?? null;
	}

	onMount(async () => {
		try {
			const res = await fetch(`${API_URL}/shop/addresses`, { credentials: 'include' });
			if (res.ok) apply(await res.json());
		} catch (e) {
			console.error('Failed to fetch address:', e);
		} finally {
			loaded = true;
		}
	});

	async function resync() {
		resyncing = true;
		error = null;
		try {
			const res = await fetch(`${API_URL}/shop/addresses/resync`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await res.json().catch(() => null);
			if (!res.ok) {
				error = (data && data.error) || $t.address.resyncFailed;
				return;
			}
			apply(data);
			showToast($t.address.resynced, 'success');
		} catch (e) {
			console.error('Failed to resync address:', e);
			error = $t.address.resyncFailed;
		} finally {
			resyncing = false;
		}
	}

	let fullName = $derived(
		address ? [address.firstName, address.lastName].filter(Boolean).join(' ') : ''
	);
	let cityLine = $derived(
		address ? [address.city, address.state, address.postalCode].filter(Boolean).join(', ') : ''
	);
</script>

{#if !loaded}
	<div class="py-4 text-center text-gray-500">{$t.address.loadingAddresses}</div>
{:else}
	<div class="space-y-3">
		{#if address}
			<div class="rounded-lg border-2 border-black bg-gray-50 p-4 text-sm">
				<p class="mb-2 text-xs font-bold text-gray-600">{$t.address.yourAuthAddress}</p>
				<p class="font-bold">{fullName || '—'}</p>
				<p>{address.line1 || '—'}</p>
				{#if address.line2}<p>{address.line2}</p>{/if}
				<p>{cityLine || '—'}</p>
				<p>{address.country || '—'}</p>
				<p class="mt-2 text-gray-600">{$t.address.phone}: {address.phoneNumber || '—'}</p>
			</div>
			{#if !address.complete}
				<div class="rounded-lg border-2 border-dashed border-yellow-600 bg-yellow-50 p-3 text-sm">
					{$t.address.incompleteNotice}
				</div>
			{/if}
		{:else}
			<div class="rounded-lg border-2 border-dashed border-yellow-600 bg-yellow-50 p-3 text-sm">
				{$t.address.noAddressNotice}
			</div>
		{/if}

		<p class="text-xs text-gray-500">{$t.address.readOnlyHint}</p>

		{#if error}
			<div class="rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
				{error}
			</div>
		{/if}

		<div class="flex flex-col gap-2 sm:flex-row">
			<a
				href={AUTH_URL}
				target="_blank"
				rel="noopener noreferrer"
				class="inline-flex flex-1 items-center justify-center gap-2 rounded-full border-2 border-black bg-white px-4 py-2 text-sm font-bold transition-all hover:border-dashed"
			>
				<ExternalLink size={16} />
				{$t.address.changeOnAuth}
			</a>
			<button
				type="button"
				onclick={resync}
				disabled={resyncing}
				class="inline-flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full border-2 border-black bg-white px-4 py-2 text-sm font-bold transition-all hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
			>
				<RefreshCw size={16} class={resyncing ? 'animate-spin' : ''} />
				{resyncing ? $t.address.resyncing : $t.address.resync}
			</button>
		</div>
	</div>
{/if}
