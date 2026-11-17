<script lang="ts">
	import { Lightbulb, X, Upload } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { showToast } from '$lib/stores';

	let open = $state(false);
	let name = $state('');
	let description = $state('');
	let vendorUrl = $state('');
	let imageUrl = $state<string | null>(null);
	let imagePreview = $state<string | null>(null);
	let uploading = $state(false);
	let sending = $state(false);
	let error = $state<string | null>(null);

	let validLink = $derived(/^https?:\/\/\S+$/i.test(vendorUrl.trim()));
	let canSend = $derived(name.trim().length > 0 && validLink && !uploading && !sending);

	function reset() {
		name = '';
		description = '';
		vendorUrl = '';
		imageUrl = null;
		imagePreview = null;
		error = null;
	}

	function close() {
		if (sending) return;
		open = false;
	}

	async function onFile(e: Event) {
		const file = (e.currentTarget as HTMLInputElement).files?.[0];
		if (!file) return;
		imagePreview = URL.createObjectURL(file);
		uploading = true;
		error = null;
		try {
			const form = new FormData();
			form.append('file', file);
			const res = await fetch(`${API_URL}/upload/image`, {
				method: 'POST',
				credentials: 'include',
				body: form
			});
			const data = await res.json();
			if (!res.ok || data.error) throw new Error(data.error ?? "couldn't upload that image");
			imageUrl = data.url;
		} catch (err) {
			error = err instanceof Error ? err.message : "couldn't upload that image";
			imagePreview = null;
			imageUrl = null;
		} finally {
			uploading = false;
		}
	}

	async function submit(e: Event) {
		e.preventDefault();
		if (!canSend) return;
		sending = true;
		error = null;
		try {
			const res = await fetch(`${API_URL}/shop/suggestions`, {
				method: 'POST',
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					name: name.trim(),
					description: description.trim(),
					vendor_url: vendorUrl.trim(),
					image: imageUrl ?? ''
				})
			});
			const data = await res.json();
			if (!res.ok) throw new Error(data.error ?? "couldn't send your suggestion");
			showToast('thanks! we got your suggestion');
			reset();
			open = false;
		} catch (err) {
			error = err instanceof Error ? err.message : "couldn't send your suggestion";
		} finally {
			sending = false;
		}
	}
</script>

<button
	onclick={() => (open = true)}
	class="fixed right-4 bottom-20 z-40 flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-white px-4 py-2 font-bold text-black transition-all duration-200 hover:border-dashed sm:right-6 sm:bottom-24 sm:px-6 sm:py-3"
	aria-label="suggest an item"
>
	<Lightbulb size={20} />
	<span class="hidden sm:inline">suggest an item</span>
</button>

{#if open}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		role="presentation"
		onclick={(e) => e.target === e.currentTarget && close()}
	>
		<form
			onsubmit={submit}
			class="relative flex max-h-[90vh] w-full max-w-md flex-col gap-3 overflow-y-auto rounded-2xl border-4 border-black bg-white p-6"
		>
			<button
				type="button"
				onclick={close}
				aria-label="close"
				class="absolute top-4 right-4 cursor-pointer"><X size={20} /></button
			>
			<div>
				<h2 class="text-xl font-bold">suggest an item</h2>
				<p class="text-sm text-gray-600">something you'd want in the shop? tell us.</p>
			</div>

			<label class="flex flex-col gap-1 text-sm font-bold">
				item name
				<input
					bind:value={name}
					maxlength="120"
					required
					placeholder="e.g. mechanical keyboard"
					class="rounded-xl border-2 border-black px-3 py-2 font-normal"
				/>
			</label>

			<div class="flex flex-col gap-1 text-sm font-bold">
				image
				{#if imagePreview}
					<div class="relative h-32 overflow-hidden rounded-xl border-2 border-black">
						<img src={imagePreview} alt="" class="h-full w-full object-contain" />
						{#if uploading}
							<div
								class="absolute inset-0 flex items-center justify-center bg-white/70 text-xs font-bold"
							>
								uploading...
							</div>
						{/if}
						<button
							type="button"
							onclick={() => {
								imagePreview = null;
								imageUrl = null;
							}}
							aria-label="remove image"
							class="absolute top-1 right-1 cursor-pointer rounded-full border-2 border-black bg-white p-0.5"
							><X size={14} /></button
						>
					</div>
				{:else}
					<label
						class="flex h-24 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border-2 border-dashed border-black font-normal text-gray-500 hover:bg-gray-50"
					>
						<Upload size={20} />
						<span class="text-xs">upload a picture</span>
						<input
							type="file"
							accept="image/png,image/jpeg,image/gif,image/webp"
							onchange={onFile}
							class="hidden"
						/>
					</label>
				{/if}
			</div>

			<label class="flex flex-col gap-1 text-sm font-bold">
				description
				<textarea
					bind:value={description}
					maxlength="1000"
					rows="3"
					placeholder="what is it, which size / color, why you want it"
					class="rounded-xl border-2 border-black px-3 py-2 font-normal"
				></textarea>
			</label>

			<label class="flex flex-col gap-1 text-sm font-bold">
				link to vendor
				<input
					bind:value={vendorUrl}
					type="url"
					required
					placeholder="https://..."
					class="rounded-xl border-2 border-black px-3 py-2 font-normal"
				/>
			</label>

			{#if error}
				<p class="rounded-lg bg-red-50 p-2 text-sm text-red-600">{error}</p>
			{/if}

			<button
				type="submit"
				disabled={!canSend}
				class="w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
				>{sending ? 'sending...' : 'send suggestion'}</button
			>
		</form>
	</div>
{/if}
