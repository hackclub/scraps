<script lang="ts">
	import { onMount } from 'svelte';
	import { fade, scale } from 'svelte/transition';
	import { getUser } from '$lib/auth-client';
	import { projectsStore, fetchProjects, type Project } from '$lib/stores';
	import { Spool, Dice5, RotateCcw, Check } from '@lucide/svelte';

	const SCRAPS_PER_HOUR = 64;

	// ---- tunables ----
	let reviewerScore = $state(2.5);
	let scoreFloorMult = $state(0.5);
	let scoreCeilMult = $state(2.0);
	let bonusMin = $state(0.5);
	let bonusMax = $state(2.0);
	let bonusSpread = $state(0.75); // how far a roll can swing from 1.0x

	let hasPowerUp = $state(true);
	let powerUpCostPct = $state(10);
	const MAX_ATTEMPTS = 3;

	let dollarsPerHour = $state(4);
	const scrapsPerDollar = $derived(SCRAPS_PER_HOUR / dollarsPerHour);

	const mockFeedback =
		'this is testing. meaning this is a test. i am now goign to epxlldoe';

	let projects = $derived($projectsStore.filter((p) => p.hours > 0));
	let selectedId = $state<number | null>(null);
	let manualHours = $state(20);

	let project = $derived(projects.find((p) => p.id === selectedId) ?? null);
	let hours = $derived(project ? (project.hoursOverride ?? project.hours) : manualHours);

	function simulateBonusEV(min: number, max: number, spread: number) {
		const N = 20000;
		const draw = () =>
			Math.min(max, Math.max(min, Math.round((1 + (Math.random() - Math.random()) * spread) * 100) / 100));
		let sum1 = 0;
		const samples: number[] = [];
		for (let i = 0; i < N; i++) {
			const r = draw();
			samples.push(r);
			sum1 += r;
		}
		const ev1 = sum1 / N;
		let sum2 = 0;
		for (let i = 0; i < N; i++) {
			const r1 = samples[i];
			sum2 += r1 >= ev1 ? r1 : draw();
		}
		const ev2 = sum2 / N;
		let sum3 = 0;
		for (let i = 0; i < N; i++) {
			const r1 = samples[i];
			if (r1 >= ev2) {
				sum3 += r1;
				continue;
			}
			const r2 = draw();
			sum3 += r2 >= ev1 ? r2 : draw();
		}
		const ev3 = sum3 / N;
		return { ev1, ev2, ev3 };
	}

	let bonusEV = $derived(simulateBonusEV(bonusMin, bonusMax, bonusSpread));

	function reviewerMultiplier(score: number): number {
		const x1 = 1,
			y1 = scoreFloorMult;
		const x2 = 2,
			y2 = 1;
		const x3 = 3,
			y3 = scoreCeilMult;
		const L1 = ((score - x2) * (score - x3)) / ((x1 - x2) * (x1 - x3));
		const L2 = ((score - x1) * (score - x3)) / ((x2 - x1) * (x2 - x3));
		const L3 = ((score - x1) * (score - x2)) / ((x3 - x1) * (x3 - x2));
		return y1 * L1 + y2 * L2 + y3 * L3;
	}

	let scoreMultiplier = $derived(reviewerMultiplier(reviewerScore));
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
		| 'powerUpOffer'
		| 'final';
	let phase = $state<Phase>('idle');

	let displayBase = $state(0); // animated counter
	let bonusRoll = $state(1); // current locked-in roll
	let spinValue = $state(1); // number flickering during a spin
	let usedReroll = $state(false);
	let usedPowerUp = $state(false);
	let attempt = $state(1); // which roll attempt is currently showing (1..3)
	let finalScraps = $state(0);
	let displayFinal = $state(0);
	let showHAPopup = $state(false);
	let lowPayoutOn = $state(false);

	const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

	function playCatSound() {
		const audio = new Audio('/audio/cat.mp3');
		audio.volume = 0.8;
		audio.play().catch(() => {});
		const duration = 1000;
		const t0 = performance.now();
		function fadeOut() {
			const k = Math.min(1, (performance.now() - t0) / duration);
			audio.volume = 0.8 * (1 - k);
			if (k < 1) requestAnimationFrame(fadeOut);
			else audio.pause();
		}
		requestAnimationFrame(fadeOut);
	}

	function triggerLowPayoutEffect() {
		showHAPopup = true;
		playCatSound();
		setTimeout(() => (showHAPopup = false), 1200);
	}

	let appearAudio: HTMLAudioElement | null = null;
	let clickAudio: HTMLAudioElement | null = null;

	function preloadClip(src: string): HTMLAudioElement {
		const audio = new Audio(src);
		audio.preload = 'auto';
		audio.load();
		return audio;
	}

	function playClipSegment(audio: HTMLAudioElement | null, startSec: number, durationMs: number) {
		if (!audio) return;
		const playFrom = () => {
			audio.currentTime = startSec;
			audio.play().catch(() => {});
			setTimeout(() => audio.pause(), durationMs);
		};
		if (audio.readyState >= 2) playFrom();
		else audio.addEventListener('canplaythrough', playFrom, { once: true });
	}

	function playBoxAppearSound() {
		playClipSegment(appearAudio, 3.5, 1000);
	}

	function playButtonClickSound() {
		playClipSegment(clickAudio, 0.2, 1500);
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

	function rollBonus(forceLow = false): number {
		if (forceLow) return bonusMin;
		// symmetric around 1.0x, EV ~1.0, clamped to [min,max]
		const raw = 1 + (Math.random() - Math.random()) * bonusSpread;
		return Math.min(bonusMax, Math.max(bonusMin, Math.round(raw * 100) / 100));
	}

	async function start() {
		playButtonClickSound();
		await sleep(1500);
		phase = 'feedback';
		playBoxAppearSound();
		displayBase = 0;
		bonusRoll = 1;
		usedReroll = false;
		usedPowerUp = false;
		attempt = 1;
		finalScraps = 0;
		displayFinal = 0;
		await sleep(900);
		phase = 'score';
		playBoxAppearSound();
		await sleep(1100);
		phase = 'base';
		playBoxAppearSound();
		await animateTo(
			() => displayBase,
			(v) => (displayBase = v),
			baseScraps,
			1200
		);
		await sleep(400);
		phase = 'rollReady';
		playBoxAppearSound();
	}

	async function doSpin(isReroll: boolean, isPowerUp = false, forceLow = false) {
		if (isReroll) usedReroll = true;
		if (isPowerUp) usedPowerUp = true;
		if (isReroll || isPowerUp) attempt += 1;
		phase = 'rolling';
		const result = rollBonus(forceLow);
		const t0 = performance.now();
		while (performance.now() - t0 < 1400) {
			spinValue = rollBonus();
			await sleep(60);
		}
		spinValue = result;
		bonusRoll = result;
		phase = 'rollDone';
		if (forceLow) triggerLowPayoutEffect();
	}

	$effect(() => {
		if (lowPayoutOn && phase === 'rollReady') {
			doSpin(false, false, true).then(() => (lowPayoutOn = false));
		}
	});

	function confirmKeep() {
		if (hasPowerUp && !usedPowerUp && attempt < MAX_ATTEMPTS) {
			phase = 'powerUpOffer';
		} else {
			finalize();
		}
	}

	async function finalize() {
		finalScraps = Math.floor(baseScraps * bonusRoll);
		phase = 'final';
		playBoxAppearSound();
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

	let effectiveScrapsPerHourNoPowerUp = $derived(SCRAPS_PER_HOUR * reviewerMultiplier(2) * bonusEV.ev2);
	let effectiveScrapsPerHourWithPowerUp = $derived(SCRAPS_PER_HOUR * reviewerMultiplier(2) * bonusEV.ev3);
	let powerUpMarginalEV = $derived(bonusEV.ev3 - bonusEV.ev2);
	let suggestedPowerUpCostScraps = $derived(Math.round(baseScraps * powerUpMarginalEV));
	let powerUpCostScraps = $derived(Math.round(baseScraps * (powerUpCostPct / 100)));

	let curvePreview = $derived(
		[1, 1.5, 2, 2.5, 3].map((s) => ({
			score: s,
			mult: reviewerMultiplier(s),
			dollarsPerHour: dollarsPerHour * reviewerMultiplier(s) * bonusEV.ev2
		}))
	);

	function scoreLabel(s: number) {
		if (s >= 2.7) return 'exceptional :D';
		if (s >= 2.3) return 'strong!';
		if (s >= 2) return 'solid';
		if (s >= 1.5) return 'needs work :/';
		return 'barely shipped';
	}

	onMount(async () => {
		appearAudio = preloadClip('/audio/buttonappear.mp3');
		clickAudio = preloadClip('/audio/buttonclick.mp3');
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
					<p class="mb-6 text-gray-600">Your project was reviewed! Go check the result.</p>
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
					{#if ['rollReady', 'rolling', 'rollDone', 'powerUpOffer', 'final'].includes(phase)}
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
										onclick={confirmKeep}
										class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-5 py-2 font-bold text-white hover:bg-gray-800"
									>
										<Check size={18} /> Keep ×{bonusRoll.toFixed(2)}
									</button>
									{#if attempt === 1 && !usedReroll}
										<button
											onclick={() => doSpin(true)}
											class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-5 py-2 font-bold hover:border-dashed"
										>
											<RotateCcw size={18} /> Reroll (binding)
										</button>
									{/if}
								</div>
								{#if attempt === 1 && !usedReroll}
									<p class="mt-2 text-xs text-gray-500">
										You have one reroll available. After that, the next roll is final.
									</p>
								{/if}
							{/if}

							{#if phase === 'powerUpOffer'}
								<div class="mt-4 rounded-xl border-2 border-dashed border-indigo-400 bg-indigo-50 p-4">
									<p class="mb-3 text-sm font-bold text-indigo-700">
										Power-up available — go again for one more binding roll?
									</p>
									<div class="flex justify-center gap-3">
										<button
											onclick={finalize}
											class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-5 py-2 font-bold text-white hover:bg-gray-800"
										>
											<Check size={18} /> Lock in ×{bonusRoll.toFixed(2)}
										</button>
										<button
											onclick={() => doSpin(false, true)}
											class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-indigo-600 bg-white px-5 py-2 font-bold text-indigo-700 hover:border-dashed"
										>
											<RotateCcw size={18} /> Go again (uses power-up)
										</button>
									</div>
									<p class="mt-2 text-xs text-gray-500">
										This is attempt {attempt} of {MAX_ATTEMPTS}. The next roll is final — no more choices.
									</p>
								</div>
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
				<input type="range" min="1" max="3" step="0.1" bind:value={reviewerScore} class="w-full" />
			</label>

			<div class="border-t-2 border-dashed border-gray-300 pt-4">
				<p class="mb-2 font-bold text-gray-500">score → multiplier curve</p>
				<p class="mb-2 text-xs text-gray-500">
					1-3 scale. Score 2 is pinned to exactly ×1 (neutral). Below 2 is always &lt; 1x — a bad
					score is on the user.
				</p>
				<label class="block">
					score 1 = ×{scoreFloorMult.toFixed(2)}
					<input type="range" min="0" max="1" step="0.05" bind:value={scoreFloorMult} class="w-full" />
				</label>
				<p class="mt-2">score 2 = ×1.00 (fixed)</p>
				<label class="mt-2 block">
					score 3 = ×{scoreCeilMult.toFixed(2)}
					<input type="range" min="1" max="3" step="0.05" bind:value={scoreCeilMult} class="w-full" />
				</label>
				<table class="mt-3 w-full border-collapse text-xs">
					<thead>
						<tr class="border-b border-gray-300 text-left text-gray-500">
							<th class="py-1">score</th>
							<th class="py-1">mult</th>
							<th class="py-1">$/hr</th>
						</tr>
					</thead>
					<tbody>
						{#each curvePreview as row (row.score)}
							<tr class="border-b border-gray-100 {row.score === 2 ? 'font-bold text-indigo-700' : ''}">
								<td class="py-1">{row.score.toFixed(1)}</td>
								<td class="py-1">×{row.mult.toFixed(2)}</td>
								<td class="py-1">${row.dollarsPerHour.toFixed(2)}</td>
							</tr>
						{/each}
					</tbody>
				</table>
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
				<label class="mt-3 flex cursor-pointer items-center justify-between gap-2">
					<span class="text-sm font-bold text-red-700">Trigger low payout</span>
					<span class="relative inline-block h-7 w-12 shrink-0 rounded-full transition-colors {lowPayoutOn
						? 'bg-red-600'
						: 'bg-gray-300'}"
					>
						<span
							class="absolute top-0.5 left-0.5 h-6 w-6 rounded-full bg-white shadow transition-transform {lowPayoutOn
								? 'translate-x-5'
								: ''}"
						></span>
					</span>
					<input type="checkbox" class="sr-only" bind:checked={lowPayoutOn} />
				</label>
			</div>

			<div class="border-t-2 border-dashed border-gray-300 pt-4 text-xs text-gray-600">
				<p>base = {hours.toFixed(1)}h × {SCRAPS_PER_HOUR.toFixed(2)}/h × {scoreMultiplier.toFixed(2)}</p>
				<p class="font-bold">= {baseScraps.toLocaleString()} scraps before bonus</p>
			</div>

			<div class="border-t-2 border-dashed border-gray-300 pt-4">
				<p class="mb-2 font-bold text-gray-500">power-up (paid 3rd attempt)</p>
				<label class="flex items-center gap-2 font-bold">
					<input type="checkbox" bind:checked={hasPowerUp} />
					player owns power-up (demo)
				</label>
				<label class="mt-2 block">
					shop price: {powerUpCostPct}% of base payout
					<input type="range" min="0" max="30" step="1" bind:value={powerUpCostPct} class="w-full" />
				</label>
				<p class="mt-1 text-xs text-gray-600">
					= {powerUpCostScraps.toLocaleString()} scraps at current hours/score
				</p>
			</div>

			<div class="border-t-2 border-dashed border-gray-300 pt-4">
				<p class="mb-2 font-bold text-gray-500">economy baseline</p>
				<label class="block">
					target $/hour: {dollarsPerHour.toFixed(2)}
					<input type="range" min="1" max="10" step="0.25" bind:value={dollarsPerHour} class="w-full" />
				</label>
				<div class="mt-3 space-y-1 rounded-lg border-2 border-black bg-gray-50 p-3 text-xs">
					<p>nominal rate: {SCRAPS_PER_HOUR.toFixed(2)} scraps/h ({scrapsPerDollar.toFixed(2)} scraps/$)</p>
					<p>reviewer mult at score 2 (neutral, fixed): ×{reviewerMultiplier(2).toFixed(3)}</p>
					<p>bonus EV, no reroll: ×{bonusEV.ev1.toFixed(3)}</p>
					<p>bonus EV, 1 free reroll (today): ×{bonusEV.ev2.toFixed(3)}</p>
					<p>bonus EV, + power-up (3 attempts): ×{bonusEV.ev3.toFixed(3)}</p>
					<p class="mt-2 font-bold">
						effective avg, no power-up: {effectiveScrapsPerHourNoPowerUp.toFixed(2)} scraps/h ≈ ${(
							effectiveScrapsPerHourNoPowerUp / scrapsPerDollar
						).toFixed(2)}/h
					</p>
					<p class="font-bold">
						effective avg, w/ power-up: {effectiveScrapsPerHourWithPowerUp.toFixed(2)} scraps/h ≈ ${(
							effectiveScrapsPerHourWithPowerUp / scrapsPerDollar
						).toFixed(2)}/h
					</p>
					<p class="mt-2 border-t border-dashed border-gray-300 pt-2">
						power-up's true marginal edge: ×{powerUpMarginalEV.toFixed(3)} → breakeven price ≈
						<span class="font-bold">{suggestedPowerUpCostScraps.toLocaleString()} scraps</span>
						({((suggestedPowerUpCostScraps / Math.max(1, baseScraps)) * 100).toFixed(1)}% of base).
						Price above this for a scrap sink with house edge; at or below it's a free-money exploit.
					</p>
				</div>
			</div>
		</div>
	</div>
</div>

{#if showHAPopup}
	<div class="pointer-events-none fixed inset-0 z-[500] flex items-center justify-center">
		<img
			src="/images/HA.png"
			alt=""
			class="w-48 sm:w-64"
			in:scale={{ duration: 150, start: 0.5 }}
			out:fade={{ duration: 1500 }}
		/>
	</div>
{/if}

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
