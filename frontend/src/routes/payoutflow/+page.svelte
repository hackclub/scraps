<script lang="ts">
	// SANDBOX PAGE — /payoutflow
	// Prototype of the Balatro-style project payout sequence:
	//   review feedback  ->  hours x reviewer score  ->  roll a final bonus (1 free reroll)
	// Nothing here touches the backend. Numbers are editable so the mechanic can be tuned.
	// Not linked in the navbar. Fold into the real review/payout flow once it feels right.
	import { onMount } from 'svelte';
	import { getUser } from '$lib/auth-client';
	import { projectsStore, fetchProjects, type Project } from '$lib/stores';
	import { Spool, Dice5, RotateCcw, Check } from '@lucide/svelte';

	const PHI = (1 + Math.sqrt(5)) / 2;
	const SCRAPS_PER_HOUR = PHI * 10;

	// ---- tunables ----
	let reviewerScore = $state(3.5); // 1..5, set by the reviewer
	let scoreFloorMult = $state(0.8); // score 1  -> this multiplier
	let scoreCeilMult = $state(1.5); // score 5  -> this multiplier
	let bonusMin = $state(0.5);
	let bonusMax = $state(2.0);
	let bonusSpread = $state(0.75); // how far a roll can swing from 1.0x

	const mockFeedback =
		'Really clean execution — the onboarding flow especially. Docs could go deeper on the deploy step, but the core loop is solid and it shipped. Nice work.';

	let projects = $derived($projectsStore.filter((p) => p.hours > 0));
	let selectedId = $state<number | null>(null);
	let manualHours = $state(20);

	let project = $derived(projects.find((p) => p.id === selectedId) ?? null);
	let hours = $derived(project ? (project.hoursOverride ?? project.hours) : manualHours);

	let scoreMultiplier = $derived(
		scoreFloorMult + ((reviewerScore - 1) / 4) * (scoreCeilMult - scoreFloorMult)
	);
	let baseScraps = $derived(Math.floor(hours * SCRAPS_PER_HOUR * scoreMultiplier));

	// ---- sequence state machine ----
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

	let displayBase = $state(0); // animated counter
	let bonusRoll = $state(1); // current locked-in roll
	let spinValue = $state(1); // number flickering during a spin
	let usedReroll = $state(false);
	let finalScraps = $state(0);
	let displayFinal = $state(0);

	const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

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

	function rollBonus(): number {
		// symmetric around 1.0x, EV ~1.0, clamped to [min,max]
		const raw = 1 + (Math.random() - Math.random()) * bonusSpread;
		return Math.min(bonusMax, Math.max(bonusMin, Math.round(raw * 100) / 100));
	}

	async function start() {
		phase = 'feedback';
		displayBase = 0;
		bonusRoll = 1;
		usedReroll = false;
		finalScraps = 0;
		displayFinal = 0;
		await sleep(900);
		phase = 'score';
		await sleep(1100);
		phase = 'base';
		await animateTo(
			() => displayBase,
			(v) => (displayBase = v),
			baseScraps,
			1200
		);
		await sleep(400);
		phase = 'rollReady';
	}

	async function doSpin(isReroll: boolean) {
		if (isReroll) usedReroll = true;
		phase = 'rolling';
		const result = rollBonus();
		const t0 = performance.now();
		while (performance.now() - t0 < 1400) {
			spinValue = rollBonus();
			await sleep(60);
		}
		spinValue = result;
		bonusRoll = result;
		phase = 'rollDone';
	}

	async function keepRoll() {
		finalScraps = Math.floor(baseScraps * bonusRoll);
		phase = 'final';
		await animateTo(
			() => displayFinal,
			(v) => (displayFinal = v),
			finalScraps,
			1400
		);
	}

	function reset() {
		phase = 'idle';
	}

	function scoreLabel(s: number) {
		if (s >= 4.5) return 'exceptional';
		if (s >= 3.5) return 'strong';
		if (s >= 2.5) return 'solid';
		if (s >= 1.5) return 'needs work';
		return 'barely shipped';
	}

	onMount(async () => {
		await getUser();
		fetchProjects();
	});
</script>

<svelte:head>
	<title>payout flow sandbox - scraps</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="mx-auto max-w-5xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-2 flex items-center gap-2">
		<Dice5 size={28} />
		<h1 class="text-4xl font-bold md:text-5xl">payout flow</h1>
	</div>
	<p class="mb-8 text-lg text-gray-600">
		Sandbox — review feedback → hours × score → roll a bonus. Backend untouched.
	</p>

	<div class="grid gap-8 lg:grid-cols-[1fr_320px]">
		<!-- ================= STAGE ================= -->
		<div
			class="relative min-h-[460px] overflow-hidden rounded-3xl border-4 border-black bg-gradient-to-b from-indigo-50 to-white p-8"
		>
			{#if phase === 'idle'}
				<div class="flex h-full flex-col items-center justify-center py-16 text-center">
					<p class="mb-2 text-2xl font-bold">
						{project ? project.name : `${manualHours}h project`}
					</p>
					<p class="mb-6 text-gray-600">Your project was reviewed. Check the result.</p>
					<button
						onclick={start}
						class="cursor-pointer rounded-full border-4 border-black bg-black px-8 py-3 text-lg font-bold text-white transition-all hover:bg-gray-800"
					>
						Check project →
					</button>
				</div>
			{:else}
				<div class="flex flex-col gap-5">
					<!-- feedback -->
					{#if ['feedback', 'score', 'base', 'rollReady', 'rolling', 'rollDone', 'final'].includes(phase)}
						<div class="animate-[slidein_.5s_ease] rounded-2xl border-2 border-black bg-white p-5">
							<p class="mb-1 text-xs font-bold tracking-wide text-gray-400 uppercase">
								Reviewer feedback
							</p>
							<p class="text-sm text-gray-700">{mockFeedback}</p>
						</div>
					{/if}

					<!-- score -->
					{#if ['score', 'base', 'rollReady', 'rolling', 'rollDone', 'final'].includes(phase)}
						<div
							class="animate-[pop_.4s_ease] rounded-2xl border-2 border-black bg-white p-5 text-center"
						>
							<p class="text-xs font-bold tracking-wide text-gray-400 uppercase">Reviewer score</p>
							<p class="text-4xl font-black">{reviewerScore.toFixed(1)}<span class="text-xl text-gray-400">/5</span></p>
							<p class="text-sm font-bold text-indigo-600">
								{scoreLabel(reviewerScore)} · ×{scoreMultiplier.toFixed(2)} payout
							</p>
						</div>
					{/if}

					<!-- base calc -->
					{#if ['base', 'rollReady', 'rolling', 'rollDone', 'final'].includes(phase)}
						<div class="rounded-2xl border-2 border-black bg-white p-5 text-center">
							<p class="mb-1 flex items-center justify-center gap-2 text-lg font-bold">
								<span>{hours.toFixed(1)}h</span>
								<span class="text-gray-400">×</span>
								<span>{scoreMultiplier.toFixed(2)}</span>
								<span class="text-gray-400">=</span>
							</p>
							<p class="flex items-center justify-center gap-2 text-4xl font-black">
								<Spool size={28} />{Math.round(displayBase).toLocaleString()}
							</p>
						</div>
					{/if}

					<!-- roll -->
					{#if ['rollReady', 'rolling', 'rollDone', 'final'].includes(phase)}
						<div
							class="rounded-2xl border-2 border-black p-5 text-center {phase === 'rolling'
								? 'bg-yellow-50'
								: 'bg-white'}"
						>
							<p class="mb-2 text-xs font-bold tracking-wide text-gray-400 uppercase">Final bonus</p>
							{#if phase === 'rollReady'}
								<button
									onclick={() => doSpin(false)}
									class="cursor-pointer rounded-full border-4 border-black bg-black px-6 py-2 font-bold text-white transition-all hover:bg-gray-800"
								>
									Roll bonus
								</button>
							{:else}
								<p
									class="text-5xl font-black tabular-nums {phase === 'rolling'
										? 'text-yellow-600'
										: bonusRoll >= 1
											? 'text-green-600'
											: 'text-red-600'}"
								>
									×{(phase === 'rolling' ? spinValue : bonusRoll).toFixed(2)}
								</p>
							{/if}

							{#if phase === 'rollDone'}
								<div class="mt-4 flex justify-center gap-3">
									<button
										onclick={keepRoll}
										class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-5 py-2 font-bold text-white hover:bg-gray-800"
									>
										<Check size={18} /> Keep ×{bonusRoll.toFixed(2)}
									</button>
									{#if !usedReroll}
										<button
											onclick={() => doSpin(true)}
											class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-5 py-2 font-bold hover:border-dashed"
										>
											<RotateCcw size={18} /> Reroll (binding)
										</button>
									{/if}
								</div>
								{#if !usedReroll}
									<p class="mt-2 text-xs text-gray-500">
										One reroll. The next result stands even if it's worse.
									</p>
								{/if}
							{/if}
						</div>
					{/if}

					<!-- final -->
					{#if phase === 'final'}
						<div
							class="animate-[pop_.4s_ease] rounded-2xl border-4 border-black bg-green-50 p-6 text-center"
						>
							<p class="text-xs font-bold tracking-wide text-gray-500 uppercase">Total payout</p>
							<p class="flex items-center justify-center gap-2 text-5xl font-black">
								<Spool size={32} />{Math.round(displayFinal).toLocaleString()}
							</p>
							<p class="mt-1 text-sm text-gray-600">
								{baseScraps.toLocaleString()} base × {bonusRoll.toFixed(2)} bonus
							</p>
							<button
								onclick={reset}
								class="mt-4 cursor-pointer rounded-full border-4 border-black px-5 py-2 font-bold hover:border-dashed"
							>
								Run again
							</button>
						</div>
					{/if}
				</div>
			{/if}
		</div>

		<!-- ================= CONTROLS ================= -->
		<div class="space-y-5 rounded-2xl border-2 border-dashed border-black p-5 text-sm">
			<div>
				<p class="mb-1 font-bold">Project</p>
				<select
					bind:value={selectedId}
					class="w-full rounded-lg border-2 border-black px-2 py-1"
				>
					<option value={null}>— manual hours —</option>
					{#each projects as p (p.id)}
						<option value={p.id}>{p.name} ({(p.hoursOverride ?? p.hours).toFixed(1)}h)</option>
					{/each}
				</select>
				{#if selectedId === null}
					<label class="mt-2 flex items-center gap-2 font-bold">
						hours
						<input type="range" min="1" max="120" bind:value={manualHours} />
						<span class="w-8">{manualHours}</span>
					</label>
				{/if}
			</div>

			<label class="block font-bold">
				reviewer score: {reviewerScore.toFixed(1)}
				<input type="range" min="1" max="5" step="0.1" bind:value={reviewerScore} class="w-full" />
			</label>

			<div class="border-t-2 border-dashed border-gray-300 pt-4">
				<p class="mb-2 font-bold text-gray-500">score → multiplier band</p>
				<label class="block">
					score 1 = ×{scoreFloorMult.toFixed(2)}
					<input type="range" min="0.3" max="1" step="0.05" bind:value={scoreFloorMult} class="w-full" />
				</label>
				<label class="mt-2 block">
					score 5 = ×{scoreCeilMult.toFixed(2)}
					<input type="range" min="1" max="2.5" step="0.05" bind:value={scoreCeilMult} class="w-full" />
				</label>
			</div>

			<div class="border-t-2 border-dashed border-gray-300 pt-4">
				<p class="mb-2 font-bold text-gray-500">bonus roll</p>
				<label class="block">
					swing ±{bonusSpread.toFixed(2)}
					<input type="range" min="0.1" max="1.5" step="0.05" bind:value={bonusSpread} class="w-full" />
				</label>
				<div class="mt-2 flex gap-2">
					<label class="flex-1">
						min ×{bonusMin.toFixed(2)}
						<input type="range" min="0" max="1" step="0.05" bind:value={bonusMin} class="w-full" />
					</label>
					<label class="flex-1">
						max ×{bonusMax.toFixed(2)}
						<input type="range" min="1" max="3" step="0.05" bind:value={bonusMax} class="w-full" />
					</label>
				</div>
			</div>

			<div class="border-t-2 border-dashed border-gray-300 pt-4 text-xs text-gray-600">
				<p>base = {hours.toFixed(1)}h × {SCRAPS_PER_HOUR.toFixed(2)}/h × {scoreMultiplier.toFixed(2)}</p>
				<p class="font-bold">= {baseScraps.toLocaleString()} scraps before bonus</p>
			</div>
		</div>
	</div>
</div>

<style>
	@keyframes slidein {
		from {
			opacity: 0;
			transform: translateY(12px);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}
	@keyframes pop {
		0% {
			opacity: 0;
			transform: scale(0.9);
		}
		60% {
			transform: scale(1.03);
		}
		100% {
			opacity: 1;
			transform: scale(1);
		}
	}
</style>
