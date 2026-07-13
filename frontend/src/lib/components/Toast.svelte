<script lang="ts">
	import { X, CheckCircle, AlertTriangle, Info } from '@lucide/svelte';
	import { toastStore, dismissToast } from '$lib/stores';

	let toasts = $derived($toastStore);
</script>

{#if toasts.length > 0}
	<div class="fixed top-4 left-1/2 z-[300] flex -translate-x-1/2 flex-col gap-2">
		{#each toasts as toast (toast.id)}
			<div
				class="flex items-center gap-3 rounded-full border-4 px-5 py-3 font-bold shadow-lg transition-all duration-200 {toast.type ===
				'error'
					? 'border-red-600 bg-red-50 text-red-700'
					: toast.type === 'success'
						? 'border-green-600 bg-green-50 text-green-700'
						: 'border-black bg-white text-black'}"
			>
				{#if toast.type === 'error'}
					<AlertTriangle size={18} />
				{:else if toast.type === 'success'}
					<CheckCircle size={18} />
				{:else}
					<Info size={18} />
				{/if}
				<span class="max-w-sm text-sm">{toast.message}</span>
				<button
					onclick={() => dismissToast(toast.id)}
					class="ml-1 cursor-pointer rounded-full p-1 transition-colors hover:bg-black/10"
				>
					<X size={14} />
				</button>
			</div>
		{/each}
	</div>
{/if}
