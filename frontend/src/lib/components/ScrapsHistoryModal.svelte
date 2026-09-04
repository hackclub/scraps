<script lang="ts">
	import { X, Spool, TrendingUp, TrendingDown } from '@lucide/svelte';
	import { API_URL } from '$lib/config';

	interface Balance {
		earned: number;
		pending: number;
		spent: number;
		balance: number;
		projectEarned: number;
		bonusEarned: number;
		shopSpent: number;
		upgradeSpent: number;
	}

	let { open = $bindable(false) } = $props();

	let balance = $state<Balance | null>(null);
	let loading = $state(false);

	async function load() {
		loading = true;
		try {
			const res = await fetch(`${API_URL}/shop/balance`, { credentials: 'include' });
			if (res.ok) balance = await res.json();
		} catch (_e) {
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		if (open && !balance && !loading) load();
	});

	function close() {
		open = false;
	}
</script>

{#if open}
	<div
		class="fixed inset-0 z-[300] flex items-center justify-center bg-black/50 p-4"
		onclick={(e) => e.target === e.currentTarget && close()}
		onkeydown={(e) => e.key === 'Escape' && close()}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-md rounded-2xl border-4 border-black bg-white p-6">
			<div class="mb-4 flex items-center justify-between">
				<h2 class="flex items-center gap-2 text-2xl font-bold"><Spool size={24} /> scraps history</h2>
				<button
					onclick={close}
					class="cursor-pointer rounded-lg p-2 transition-colors hover:bg-gray-100"
					aria-label="Close"
				>
					<X size={20} />
				</button>
			</div>

			{#if loading || !balance}
				<p class="py-6 text-center text-gray-500">loading…</p>
			{:else}
				<div class="mb-4 rounded-xl border-2 border-black bg-gray-50 p-4 text-center">
					<p class="text-sm font-bold text-gray-500">current balance</p>
					<p class="text-3xl font-black">{balance.balance.toLocaleString()}</p>
				</div>

				<div class="mb-4">
					<p class="mb-2 flex items-center gap-1 font-bold text-green-700">
						<TrendingUp size={16} /> earned — {balance.earned.toLocaleString()}
					</p>
					<div class="flex flex-col gap-1 pl-5 text-sm text-gray-600">
						<div class="flex justify-between">
							<span>projects shipped</span>
							<span class="font-bold">{balance.projectEarned.toLocaleString()}</span>
						</div>
						<div class="flex justify-between">
							<span>bonuses</span>
							<span class="font-bold">{balance.bonusEarned.toLocaleString()}</span>
						</div>
						{#if balance.pending > 0}
							<div class="flex justify-between text-yellow-700">
								<span>pending (awaiting ship)</span>
								<span class="font-bold">{balance.pending.toLocaleString()}</span>
							</div>
						{/if}
					</div>
				</div>

				<div>
					<p class="mb-2 flex items-center gap-1 font-bold text-red-700">
						<TrendingDown size={16} /> spent — {balance.spent.toLocaleString()}
					</p>
					<div class="flex flex-col gap-1 pl-5 text-sm text-gray-600">
						<div class="flex justify-between">
							<span>shop</span>
							<span class="font-bold">{balance.shopSpent.toLocaleString()}</span>
						</div>
						<div class="flex justify-between">
							<span>refinery upgrades</span>
							<span class="font-bold">{balance.upgradeSpent.toLocaleString()}</span>
						</div>
					</div>
				</div>
			{/if}
		</div>
	</div>
{/if}
