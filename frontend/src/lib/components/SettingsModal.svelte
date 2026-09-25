<script lang="ts">
	import { X } from '@lucide/svelte';
	import { onMount } from 'svelte';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';
	import { showToast, onboardingSandbox } from '$lib/stores';

	let { onClose }: { onClose: () => void } = $props();

	let loading = $state(true);
	let saving = $state(false);
	let error = $state<string | null>(null);

	let preferredName = $state('');
	let phone = $state('');
	let addressLine1 = $state('');
	let addressLine2 = $state('');
	let addressCity = $state('');
	let addressState = $state('');
	let addressPostalCode = $state('');
	let addressCountry = $state('');

	onMount(async () => {
		try {
			const res = await fetch(`${API_URL}/user/settings`, { credentials: 'include' });
			if (res.ok) {
				const data = await res.json();
				preferredName = data.preferredName ?? '';
				phone = data.phone ?? '';
				addressLine1 = data.addressLine1 ?? '';
				addressLine2 = data.addressLine2 ?? '';
				addressCity = data.addressCity ?? '';
				addressState = data.addressState ?? '';
				addressPostalCode = data.addressPostalCode ?? '';
				addressCountry = data.addressCountry ?? '';
			} else {
				error = $t.settings.failedToLoad;
			}
		} catch (e) {
			console.error('Failed to load settings:', e);
			error = $t.settings.failedToLoad;
		} finally {
			loading = false;
		}
	});

	function handleRedoOnboarding() {
		onboardingSandbox.set(Date.now());
		onClose();
	}

	async function handleSave() {
		saving = true;
		error = null;
		try {
			const res = await fetch(`${API_URL}/user/settings`, {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({
					preferredName,
					phone,
					addressLine1,
					addressLine2,
					addressCity,
					addressState,
					addressPostalCode,
					addressCountry
				})
			});
			if (!res.ok) throw new Error();
			showToast($t.settings.saved, 'success');
			onClose();
		} catch (e) {
			console.error('Failed to save settings:', e);
			error = $t.settings.failedToSave;
		} finally {
			saving = false;
		}
	}
</script>

<div
	class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
	onclick={(e) => e.target === e.currentTarget && onClose()}
	onkeydown={(e) => e.key === 'Escape' && onClose()}
	role="dialog"
	tabindex="-1"
>
	<div
		class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border-4 border-black bg-white p-6"
	>
		<div class="mb-6 flex items-start justify-between gap-4">
			<h2 class="text-2xl font-bold">{$t.settings.settings}</h2>
			<button
				type="button"
				onclick={onClose}
				aria-label="Close"
				class="flex h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded-full border-2 border-black transition-all hover:border-dashed"
			>
				<X size={16} />
			</button>
		</div>

		{#if error}
			<div class="mb-4 rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
				{error}
			</div>
		{/if}

		{#if loading}
			<div class="py-8 text-center text-gray-500">{$t.common.loading}</div>
		{:else}
			<div class="space-y-5">
				<div>
					<label for="preferredName" class="mb-1 block text-sm font-bold"
						>{$t.settings.preferredName}</label
					>
					<input
						id="preferredName"
						type="text"
						bind:value={preferredName}
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
					<p class="mt-1 text-xs text-gray-500">{$t.settings.preferredNameHint}</p>
				</div>

				<div class="border-t-2 border-dashed border-gray-300 pt-5">
					<p class="mb-1 font-bold">{$t.settings.yourAddress}</p>
					<p class="mb-3 text-xs text-gray-500">{$t.settings.addressHint}</p>

					<div class="space-y-3">
						<label class="block text-xs font-bold text-gray-600">
							{$t.address.addressLine1}
							<input
								type="text"
								bind:value={addressLine1}
								class="mt-1 w-full rounded-lg border-2 border-black px-3 py-2 text-sm focus:border-dashed focus:outline-none"
							/>
						</label>
						<label class="block text-xs font-bold text-gray-600">
							{$t.address.addressLine2}
							<input
								type="text"
								bind:value={addressLine2}
								class="mt-1 w-full rounded-lg border-2 border-black px-3 py-2 text-sm focus:border-dashed focus:outline-none"
							/>
						</label>
						<div class="grid grid-cols-3 gap-2">
							<label class="text-xs font-bold text-gray-600">
								{$t.address.city}
								<input
									type="text"
									bind:value={addressCity}
									class="mt-1 w-full rounded-lg border-2 border-black px-3 py-2 text-sm focus:border-dashed focus:outline-none"
								/>
							</label>
							<label class="text-xs font-bold text-gray-600">
								{$t.address.state}
								<input
									type="text"
									bind:value={addressState}
									class="mt-1 w-full rounded-lg border-2 border-black px-3 py-2 text-sm focus:border-dashed focus:outline-none"
								/>
							</label>
							<label class="text-xs font-bold text-gray-600">
								{$t.address.postalCode}
								<input
									type="text"
									bind:value={addressPostalCode}
									class="mt-1 w-full rounded-lg border-2 border-black px-3 py-2 text-sm focus:border-dashed focus:outline-none"
								/>
							</label>
						</div>
						<label class="block text-xs font-bold text-gray-600">
							{$t.address.country}
							<input
								type="text"
								bind:value={addressCountry}
								class="mt-1 w-full rounded-lg border-2 border-black px-3 py-2 text-sm focus:border-dashed focus:outline-none"
							/>
						</label>
						<label class="block text-xs font-bold text-gray-600">
							{$t.address.phone}
							<input
								type="tel"
								bind:value={phone}
								class="mt-1 w-full rounded-lg border-2 border-black px-3 py-2 text-sm focus:border-dashed focus:outline-none"
							/>
						</label>
					</div>
				</div>

				<div class="border-t-2 border-dashed border-gray-300 pt-5">
					<p class="mb-1 font-bold">{$t.settings.redoOnboarding}</p>
					<p class="mb-3 text-xs text-gray-500">{$t.settings.redoOnboardingHint}</p>
					<button
						type="button"
						onclick={handleRedoOnboarding}
						class="w-full cursor-pointer rounded-full border-2 border-black bg-white px-4 py-2 font-bold transition-all hover:border-dashed"
					>
						{$t.settings.redoOnboardingButton}
					</button>
				</div>
			</div>

			<div class="mt-6">
				<button
					onclick={handleSave}
					disabled={saving}
					class="w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
				>
					{saving ? $t.settings.saving : $t.settings.save}
				</button>
			</div>
		{/if}
	</div>
</div>
