<script lang="ts">
	import { Spool } from '@lucide/svelte';

	let { onFinal }: { onFinal?: (reward: number) => void } = $props();

	const REWARDS = [
		{ amount: 1, weight: 55, color: 'text-gray-600', bg: 'bg-gray-100' },
		{ amount: 5, weight: 30, color: 'text-green-600', bg: 'bg-green-100' },
		{ amount: 10, weight: 12, color: 'text-blue-600', bg: 'bg-blue-100' },
		{ amount: 50, weight: 3, color: 'text-yellow-600', bg: 'bg-yellow-100' }
	];
	const TOTAL_WEIGHT = REWARDS.reduce((n, r) => n + r.weight, 0);

	function rollReward() {
		let roll = Math.random() * TOTAL_WEIGHT;
		for (const r of REWARDS) {
			if (roll < r.weight) return r;
			roll -= r.weight;
		}
		return REWARDS[0];
	}

	type Phase = 'idle' | 'spinning' | 'done';
	let phase = $state<Phase>('idle');
	let spinAmount = $state(5);
	let landed = $state(REWARDS[0]);

	function sleep(ms: number) {
		return new Promise((r) => setTimeout(r, ms));
	}

	async function pull() {
		phase = 'spinning';
		const result = rollReward();
		const t0 = performance.now();
		while (performance.now() - t0 < 1100) {
			spinAmount = REWARDS[Math.floor(Math.random() * REWARDS.length)].amount;
			await sleep(60);
		}
		landed = result;
		phase = 'done';
		await sleep(1800);
		onFinal?.(result.amount);
	}
</script>

<div class="w-[min(92vw,26rem)] rounded-2xl border-4 border-black bg-white p-4 shadow-xl">
	<p class="text-sm font-bold">you can win 1, 5, 10 or 50 scraps</p>
	<p class="mb-2 text-xs font-bold text-gray-500">ONBOARDING GACHAPON</p>
	<div class="flex items-center gap-3 text-sm">
		<div
			class="grid h-16 w-16 shrink-0 place-items-center rounded-full border-4 border-black bg-red-100 {phase ===
			'spinning'
				? 'animate-bounce'
				: ''}"
		>
			🎱
		</div>
		{#if phase === 'idle'}
			<button
				onclick={pull}
				class="flex-1 cursor-pointer rounded-full border-4 border-black bg-black px-4 py-2 text-sm font-bold text-white transition-all hover:bg-gray-800"
			>
				Pull →
			</button>
		{:else if phase === 'spinning'}
			<p class="flex flex-1 items-center gap-1 text-2xl font-black text-gray-400">
				<Spool size={20} />{spinAmount}
			</p>
		{:else}
			<p class="flex flex-1 items-center gap-1 text-2xl font-black {landed.color}">
				<Spool size={20} />+{landed.amount} scraps!
			</p>
		{/if}
	</div>
</div>
