<script lang="ts">
	import { X, AlertTriangle } from '@lucide/svelte';
	import { errorStore, clearError } from '$lib/stores';
	import { t } from '$lib/i18n';

	let error = $derived($errorStore);
</script>

{#if error}
	<div
		class="fixed inset-0 z-[200] flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && clearError()}
		onkeydown={(e) => e.key === 'Escape' && clearError()}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-red-600 bg-white p-6">
			<div class="mb-4 flex items-start justify-between">
				<div class="flex items-center gap-3">
					<div class="flex h-10 w-10 items-center justify-center rounded-full bg-red-100">
						<AlertTriangle size={24} class="text-red-600" />
					</div>
					<h2 class="text-2xl font-bold text-red-600">{error.title || $t.common.error}</h2>
				</div>
				<button
					onclick={clearError}
					class="cursor-pointer rounded-lg p-2 transition-colors hover:bg-gray-100"
					aria-label={$t.common.close}
				>
					<X size={20} />
				</button>
			</div>
			<p class="mb-6 text-gray-600">{error.message}</p>
			{#if error.details}
				<div
					class="mb-6 overflow-x-auto rounded-lg bg-gray-100 p-3 font-mono text-sm text-gray-500"
				>
					{error.details}
				</div>
			{/if}
			<button
				onclick={clearError}
				class="w-full cursor-pointer rounded-full border-4 border-red-600 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:border-dashed"
			>
				{$t.common.dismiss}
			</button>
		</div>
	</div>
{/if}
