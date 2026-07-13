<script lang="ts">
	import { t } from '$lib/i18n';

	let {
		title,
		message,
		confirmText = $t.common.confirm,
		cancelText = $t.common.cancel,
		confirmStyle = 'primary',
		loading = false,
		onConfirm,
		onCancel
	}: {
		title: string;
		message: string;
		confirmText?: string;
		cancelText?: string;
		confirmStyle?: 'primary' | 'success' | 'warning' | 'danger';
		loading?: boolean;
		onConfirm: () => void;
		onCancel: () => void;
	} = $props();

	function getConfirmClass(): string {
		const base =
			'flex-1 px-4 py-2 rounded-full font-bold border-4 border-black transition-all duration-200 disabled:opacity-50 cursor-pointer hover:border-dashed';
		switch (confirmStyle) {
			case 'success':
				return `${base} bg-green-600 text-white`;
			case 'warning':
				return `${base} bg-yellow-500 text-white`;
			case 'danger':
				return `${base} bg-red-600 text-white`;
			default:
				return `${base} bg-black text-white`;
		}
	}

	function handleBackdropClick(e: MouseEvent) {
		if (e.target === e.currentTarget) {
			onCancel();
		}
	}
</script>

<div
	class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
	onclick={handleBackdropClick}
	onkeydown={(e) => e.key === 'Escape' && onCancel()}
	role="dialog"
	tabindex="-1"
>
	<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
		<h2 class="mb-4 text-2xl font-bold">{title}</h2>
		<p class="mb-6 text-gray-600">
			{@html message}
		</p>
		<div class="flex gap-3">
			<button
				onclick={onCancel}
				disabled={loading}
				class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
			>
				{cancelText}
			</button>
			<button onclick={onConfirm} disabled={loading} class={getConfirmClass()}>
				{loading ? $t.common.loading : confirmText}
			</button>
		</div>
	</div>
</div>
