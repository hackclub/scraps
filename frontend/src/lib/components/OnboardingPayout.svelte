<script lang="ts">
	import { fade } from 'svelte/transition';
	import { Spool, Check, RotateCcw } from '@lucide/svelte';

	let { onFinal }: { onFinal?: (finalMult: number) => void } = $props();

	// Fixed example project. Same formula the real payout uses (ScrapsService):
	// scraps = floor(hours * 64 * reviewerMultiplier(score)), score 2 pinned to ×1.00.
	const HOURS = 8;
	const SCRAPS_PER_HOUR = 64;
	const SCORE = 2;
	const SCORE_FLOOR_MULT = 0.5;
	const SCORE_CEIL_MULT = 2.0;
	const BONUS_SPREAD = 0.75;
	const BONUS_MIN = 0.5;
	const BONUS_MAX = 2.0;

	function reviewerMultiplier(score: number): number {
		const x1 = 1,
			y1 = SCORE_FLOOR_MULT;
		const x2 = 2,
			y2 = 1.0;
		const x3 = 3,
			y3 = SCORE_CEIL_MULT;
		const L1 = ((score - x2) * (score - x3)) / ((x1 - x2) * (x1 - x3));
		const L2 = ((score - x1) * (score - x3)) / ((x2 - x1) * (x2 - x3));
		const L3 = ((score - x1) * (score - x2)) / ((x3 - x1) * (x3 - x2));
		return y1 * L1 + y2 * L2 + y3 * L3;
	}

	const scoreMult = reviewerMultiplier(SCORE);
	const baseScraps = Math.floor(HOURS * SCRAPS_PER_HOUR * scoreMult);

	function rollBonus(): number {
		const raw = 1 + (Math.random() - Math.random()) * BONUS_SPREAD;
		return Math.min(BONUS_MAX, Math.max(BONUS_MIN, Math.round(raw * 100) / 100));
	}

	type Phase =
		| 'idle'
		| 'feedback'
		| 'score'
		| 'base'
		| 'rollReady'
		| 'rolling'
		| 'rollDone'
		| 'final';
	let phase = $state<Phase>('idle');
	let displayBase = $state(0);
	let spinMult = $state(1);
	let landedMult = $state(1);
	let displayFinal = $state(0);
	let attempt = $state(1);
	let usedReroll = $state(false);

	function sleep(ms: number) {
		return new Promise((r) => setTimeout(r, ms));
	}

	function animateTo(get: () => number, set: (v: number) => void, target: number, ms: number) {
		return new Promise<void>((resolve) => {
			const start = get();
			const t0 = performance.now();
			function frame(now: number) {
				const k = Math.min(1, (now - t0) / ms);
				const eased = 1 - Math.pow(1 - k, 3);
				set(start + (target - start) * eased);
				if (k < 1) requestAnimationFrame(frame);
				else {
					set(target);
					resolve();
				}
			}
			requestAnimationFrame(frame);
		});
	}

	async function checkProject() {
		phase = 'feedback';
		await sleep(800);
		phase = 'score';
		await sleep(800);
		phase = 'base';
		await animateTo(
			() => displayBase,
			(v) => (displayBase = v),
			baseScraps,
			1000
		);
		await sleep(300);
		phase = 'rollReady';
	}

	async function spin() {
		phase = 'rolling';
		const target = rollBonus();
		const t0 = performance.now();
		while (performance.now() - t0 < 1200) {
			spinMult = rollBonus();
			await sleep(55);
		}
		spinMult = target;
		landedMult = target;
		phase = 'rollDone';
	}

	function reroll() {
		usedReroll = true;
		attempt = 2;
		spin();
	}

	async function keep() {
		const finalMult = landedMult;
		phase = 'final';
		await animateTo(
			() => displayFinal,
			(v) => (displayFinal = v),
			Math.round(baseScraps * finalMult),
			900
		);
		onFinal?.(finalMult);
	}
</script>

<div class="w-[min(92vw,26rem)] rounded-2xl border-4 border-black bg-white p-4 shadow-xl">
	{#if phase === 'idle'}
		<div class="py-3 text-center">
			<p class="mb-1 text-lg font-bold">“my first scrap”</p>
			<p class="mb-4 text-sm text-gray-600">Your project was reviewed! Go check the result.</p>
			<button
				onclick={checkProject}
				class="cursor-pointer rounded-full border-4 border-black bg-black px-5 py-2 text-sm font-bold text-white transition-all hover:bg-gray-800"
			>
				Check project →
			</button>
		</div>
	{:else}
		<div class="space-y-2 text-sm">
			<div class="rounded-lg bg-gray-50 p-2 text-xs text-gray-600" transition:fade={{ duration: 150 }}>
				reviewer: “get ready to enjoy scraps”
			</div>

			{#if phase !== 'feedback'}
				<div class="flex items-center justify-between" transition:fade={{ duration: 150 }}>
					<span>score <strong>{SCORE}</strong>/3</span>
					<strong>×{scoreMult.toFixed(2)}</strong>
				</div>
			{/if}

			{#if !['feedback', 'score'].includes(phase)}
				<div
					class="flex items-center justify-between border-t-2 border-black pt-2"
					transition:fade={{ duration: 150 }}
				>
					<span>base ({HOURS}h × {SCRAPS_PER_HOUR})</span>
					<strong class="flex items-center gap-1"><Spool size={14} />{Math.round(displayBase)}</strong>
				</div>
			{/if}

			{#if ['rollReady', 'rolling', 'rollDone', 'final'].includes(phase)}
				<div class="border-t-2 border-black pt-2 text-center" transition:fade={{ duration: 150 }}>
					{#if phase === 'rollReady'}
						<button
							onclick={spin}
							class="cursor-pointer rounded-full border-4 border-black bg-black px-5 py-2 text-sm font-bold text-white transition-all hover:bg-gray-800"
						>
							Roll bonus
						</button>
					{:else}
						<p
							class="text-3xl font-black tabular-nums {phase === 'rolling'
								? 'text-yellow-600'
								: landedMult >= 1
									? 'text-green-600'
									: 'text-red-600'}"
						>
							×{(phase === 'rolling' ? spinMult : landedMult).toFixed(2)}
						</p>
					{/if}

					{#if phase === 'rollDone'}
						<div class="mt-2 flex justify-center gap-2">
							<button
								onclick={keep}
								class="flex cursor-pointer items-center gap-1 rounded-full border-4 border-black bg-black px-4 py-1.5 text-xs font-bold text-white hover:bg-gray-800"
							>
								<Check size={14} /> Keep ×{landedMult.toFixed(2)}
							</button>
							{#if attempt === 1 && !usedReroll}
								<button
									onclick={reroll}
									class="flex cursor-pointer items-center gap-1 rounded-full border-4 border-black px-4 py-1.5 text-xs font-bold hover:border-dashed"
								>
									<RotateCcw size={14} /> Reroll (binding)
								</button>
							{/if}
						</div>
					{/if}
				</div>
			{/if}

			{#if phase === 'final'}
				<div class="border-t-2 border-black pt-2 text-center" transition:fade={{ duration: 150 }}>
					<p class="text-xs font-bold tracking-wide text-gray-500 uppercase">total payout</p>
					<p class="flex items-center justify-center gap-1 text-3xl font-black">
						<Spool size={20} />{Math.round(displayFinal)}
					</p>
				</div>
			{/if}
		</div>
	{/if}
</div>
