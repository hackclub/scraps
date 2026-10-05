<script lang="ts">
	import { onMount } from 'svelte';
	import { fade, fly } from 'svelte/transition';
	import { Spool, PartyPopper, ChevronRight, X, Dices, Check, RotateCcw } from '@lucide/svelte';
	import { projectsStore, type Project } from '$lib/stores';
	import { API_URL, serverConfig } from '$lib/config';
	import { reviewerScoreMultiplier } from '$lib/utils';
	import ProjectPlaceholder from '$lib/components/ProjectPlaceholder.svelte';

	const SCRAPS_PER_HOUR = serverConfig.scrapsPerHour ?? 64;
	const FALLBACK_SCORE_MULTS = { floor: 0.5, neutral: 1.0, ceil: 2.0 };
	const GRADIENTS = [
		'from-blue-50',
		'from-emerald-50',
		'from-purple-50',
		'from-pink-50',
		'from-amber-50'
	];

	type Stage = 'intro' | 'feedback' | 'multiplier' | 'calc';

	let checked = $state(false);
	let show = $state(false);
	let closing = $state(false);
	let stage = $state<Stage>('intro');
	let celebProject = $state<Project | null>(null);
	let feedback = $state('');
	let hours = $state(0);
	let reviewerScore = $state(2);
	let scoreMultiplier = $state(1);
	let scrapsAwarded = $state(0);
	let displayTotal = $state(0);

	interface PayoutRoll {
		status: 'open' | 'rolled' | 'final' | 'cancelled';
		baseScraps: number;
		roll1: number | null;
		roll2: number | null;
		finalMultiplier: number | null;
		finalScraps: number | null;
		minMultiplier: number;
		maxMultiplier: number;
	}
	let payoutRoll = $state<PayoutRoll | null>(null);
	let rolling = $state(false);
	let spinValue = $state(1);
	let rollError = $state<string | null>(null);
	let deciding = $state(false);

	async function fetchPayoutRoll(projectId: number) {
		try {
			const res = await fetch(`${API_URL}/projects/${projectId}/payout-roll`, {
				credentials: 'include'
			});
			payoutRoll = res.ok ? ((await res.json()).payoutRoll ?? null) : null;
		} catch {
			payoutRoll = null;
		}
	}

	async function payoutAction(action: 'roll' | 'keep'): Promise<boolean> {
		if (!celebProject) return false;
		rollError = null;
		try {
			const res = await fetch(`${API_URL}/projects/${celebProject.id}/payout-roll/${action}`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await res.json();
			if (!res.ok) {
				rollError = data.error ?? 'Something went wrong';
				return false;
			}
			payoutRoll = data.payoutRoll;
			return true;
		} catch {
			rollError = 'Something went wrong';
			return false;
		}
	}

	async function rollBonus() {
		if (deciding || !payoutRoll) return;
		deciding = true;
		playButtonClickSound();
		rolling = true;
		const lo = payoutRoll.minMultiplier;
		const hi = payoutRoll.maxMultiplier;
		const spin = setInterval(() => {
			spinValue = Math.round((lo + Math.random() * (hi - lo)) * 100) / 100;
		}, 60);
		const [ok] = await Promise.all([payoutAction('roll'), sleep(1100)]);
		clearInterval(spin);
		rolling = false;
		deciding = false;
		if (ok) playBoxAppearSound();
	}

	async function keepPayout() {
		if (deciding) return;
		deciding = true;
		playButtonClickSound();
		await payoutAction('keep');
		deciding = false;
	}

	let pendingMultiplier = $derived(
		payoutRoll?.status === 'rolled' ? (payoutRoll.roll1 ?? 1) : (payoutRoll?.finalMultiplier ?? 1)
	);

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

	const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

	onMount(() => {
		appearAudio = preloadClip('/audio/buttonappear.mp3');
		clickAudio = preloadClip('/audio/buttonclick.mp3');
	});

	function seenKey(id: number, amount: number) {
		return `payout-celebration-seen:${id}:${amount}`;
	}

	function markSeen(project: Project) {
		try {
			localStorage.setItem(seenKey(project.id, project.scrapsAwarded ?? 0), '1');
		} catch (_e) {}
	}

	function alreadySeen(project: Project) {
		try {
			return localStorage.getItem(seenKey(project.id, project.scrapsAwarded ?? 0)) === '1';
		} catch (_e) {
			return false;
		}
	}

	function gradientFor(id: number) {
		return GRADIENTS[id % GRADIENTS.length];
	}

	async function openCelebration(project: Project) {
		celebProject = project;
		stage = 'intro';
		displayTotal = 0;

		try {
			const [projectRes, reviewsRes] = await Promise.all([
				fetch(`${API_URL}/projects/${project.id}`, { credentials: 'include' }),
				fetch(`${API_URL}/projects/${project.id}/reviews`, { credentials: 'include' })
			]);

			const detail = projectRes.ok ? await projectRes.json() : null;
			const reviews = reviewsRes.ok ? await reviewsRes.json() : [];

			const p = detail?.project ?? project;
			hours = p.hoursOverride ?? p.hours ?? project.hoursOverride ?? project.hours ?? 0;
			scrapsAwarded = project.scrapsAwarded ?? 0;

			const approvedReview = [...reviews]
				.reverse()
				.find((r: { action: string }) => r.action === 'approved');
			feedback = approvedReview?.feedbackForAuthor || '';
			reviewerScore = approvedReview?.reviewerScore ?? 2;
			scoreMultiplier = reviewerScoreMultiplier(
				reviewerScore,
				serverConfig.reviewerScoreFloorMult ?? FALLBACK_SCORE_MULTS.floor,
				serverConfig.reviewerScoreNeutralMult ?? FALLBACK_SCORE_MULTS.neutral,
				serverConfig.reviewerScoreCeilMult ?? FALLBACK_SCORE_MULTS.ceil
			);
		} catch (_e) {
			hours = project.hoursOverride ?? project.hours ?? 0;
			scrapsAwarded = project.scrapsAwarded ?? 0;
			feedback = '';
			reviewerScore = 2;
			scoreMultiplier = 1;
		}

		await fetchPayoutRoll(project.id);
		show = true;
		playBoxAppearSound();
	}

	function animateTotal() {
		const target = scrapsAwarded;
		const start = performance.now();
		const duration = 1200;
		function frame(now: number) {
			const k = Math.min(1, (now - start) / duration);
			displayTotal = Math.round(target * (1 - Math.pow(1 - k, 3)));
			if (k < 1) requestAnimationFrame(frame);
		}
		requestAnimationFrame(frame);
	}

	async function next() {
		playButtonClickSound();
		await sleep(1500);
		if (stage === 'intro') stage = 'feedback';
		else if (stage === 'feedback') stage = 'multiplier';
		else if (stage === 'multiplier') {
			stage = 'calc';
			animateTotal();
		}
		playBoxAppearSound();
	}

	async function close() {
		if (payoutRoll && (payoutRoll.status === 'open' || payoutRoll.status === 'rolled')) {
			await payoutAction('keep');
		}
		if (celebProject) markSeen(celebProject);
		closing = true;
		setTimeout(() => {
			show = false;
			closing = false;
			celebProject = null;
		}, 300);
	}

	$effect(() => {
		if (checked || show) return;
		const projects = $projectsStore;
		if (projects.length === 0) return;
		checked = true;

		const candidate = projects
			.filter((p) => p.status === 'shipped' && (p.scrapsAwarded ?? 0) > 0 && !alreadySeen(p))
			.sort(
				(a, b) => new Date(b.updatedAt ?? 0).getTime() - new Date(a.updatedAt ?? 0).getTime()
			)[0];

		if (candidate) {
			setTimeout(() => openCelebration(candidate), 1200);
		}
	});
</script>

{#if show && celebProject}
	<div
		class="fixed inset-0 z-[400] flex items-center justify-center bg-black/60 p-4"
		transition:fade={{ duration: closing ? 300 : 500 }}
	>
		<div
			class="relative h-[520px] w-full max-w-lg overflow-hidden rounded-3xl border-4 border-black"
		>
			{#if stage === 'intro'}
				<div class="absolute inset-0" transition:fly={{ x: 300, duration: 400 }}>
					<div class="absolute inset-0">
						{#if celebProject.image}
							<img src={celebProject.image} alt="" class="h-full w-full object-cover" />
						{:else}
							<ProjectPlaceholder seed={celebProject.id} />
						{/if}
						<div
							class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/40 to-black/10"
						></div>
					</div>
					<button
						onclick={close}
						class="absolute top-4 right-4 cursor-pointer rounded-full bg-white/20 p-2 text-white hover:bg-white/30"
						aria-label="Close"
					>
						<X size={18} />
					</button>
					<div
						class="absolute inset-x-0 bottom-0 flex flex-col items-center gap-4 p-8 text-center text-white"
					>
						<PartyPopper size={40} />
						<h2 class="text-3xl font-black wrap-break-word">
							{celebProject.name} has been approved!
						</h2>
						<button
							onclick={next}
							class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-white bg-white px-6 py-3 font-bold text-black transition-all hover:bg-gray-100"
						>
							Check out the results
							<ChevronRight size={18} />
						</button>
					</div>
				</div>
			{:else}
				{#key stage}
					<div
						class="absolute inset-0 flex flex-col items-center justify-center gap-5 bg-gradient-to-b {gradientFor(
							celebProject.id
						)} to-white p-8 text-center"
						in:fly={{ x: -300, duration: 400 }}
						out:fly={{ x: 300, duration: 400 }}
					>
						{#if stage === 'feedback'}
							<p class="text-xs font-bold tracking-wide text-gray-400 uppercase">
								Reviewer feedback
							</p>
							<p class="max-h-64 overflow-y-auto text-lg text-gray-700">
								{feedback || 'Nice work: this shipped!'}
							</p>
							<button
								onclick={next}
								class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-6 py-3 font-bold text-white transition-all hover:bg-gray-800"
							>
								Continue
								<ChevronRight size={18} />
							</button>
						{:else if stage === 'multiplier'}
							<p class="text-xs font-bold tracking-wide text-gray-400 uppercase">Reviewer score</p>
							<p class="text-6xl font-black text-indigo-600">{reviewerScore.toFixed(1)}/3</p>
							<p class="text-gray-600">×{scoreMultiplier.toFixed(2)} applied to your payout</p>
							<button
								onclick={next}
								class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-6 py-3 font-bold text-white transition-all hover:bg-gray-800"
							>
								See your payout
								<ChevronRight size={18} />
							</button>
						{:else if stage === 'calc'}
							<p class="text-xs font-bold tracking-wide text-gray-400 uppercase">Payout</p>
							<p class="flex items-center justify-center gap-2 text-lg font-bold text-gray-500">
								<span>{hours.toFixed(1)}h</span>
								<span>×</span>
								<span>{SCRAPS_PER_HOUR.toFixed(2)}/h</span>
								<span>×</span>
								<span>{scoreMultiplier.toFixed(2)}</span>
							</p>
							<p class="flex items-center justify-center gap-2 text-5xl font-black">
								<Spool size={36} />{displayTotal.toLocaleString()}
							</p>
							{#if payoutRoll && payoutRoll.status !== 'cancelled'}
								{#if rolling || payoutRoll.status !== 'open'}
									<p
										class="text-4xl font-black tabular-nums {rolling
											? 'text-gray-400'
											: pendingMultiplier >= 1
												? 'text-green-600'
												: 'text-red-600'}"
									>
										×{(rolling ? spinValue : pendingMultiplier).toFixed(2)}
									</p>
									{#if !rolling}
										<p class="text-lg font-bold">
											= {Math.floor(payoutRoll.baseScraps * pendingMultiplier).toLocaleString()} scraps
										</p>
									{/if}
								{/if}
								{#if rollError}
									<p class="text-sm font-bold text-red-600">{rollError}</p>
								{/if}
								{#if !rolling && payoutRoll.status === 'open' && !rollError}
									<p class="text-sm text-gray-600">
										take your payout, or roll for a bonus between ×{payoutRoll.minMultiplier.toFixed(
											2
										)} and ×{payoutRoll.maxMultiplier.toFixed(2)}. you get one reroll, and the
										reroll is final.
									</p>
									<div class="flex flex-wrap justify-center gap-3">
										<button
											onclick={keepPayout}
											disabled={deciding}
											class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-5 py-3 font-bold transition-all hover:border-dashed disabled:opacity-50"
										>
											<Check size={18} /> Take payout
										</button>
										<button
											onclick={rollBonus}
											disabled={deciding}
											class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-5 py-3 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
										>
											<Dices size={18} /> Roll for a bonus
										</button>
									</div>
								{:else if !rolling && payoutRoll.status === 'rolled'}
									<div class="flex flex-wrap justify-center gap-3">
										<button
											onclick={keepPayout}
											disabled={deciding}
											class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-5 py-3 font-bold transition-all hover:border-dashed disabled:opacity-50"
										>
											<Check size={18} /> Keep ×{pendingMultiplier.toFixed(2)}
										</button>
										<button
											onclick={rollBonus}
											disabled={deciding}
											class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-5 py-3 font-bold text-white transition-all hover:bg-gray-800 disabled:opacity-50"
										>
											<RotateCcw size={18} /> Reroll (final)
										</button>
									</div>
									<p class="text-xs text-gray-500">
										if you reroll, you have to keep whatever you get
									</p>
								{:else if !rolling}
									<button
										onclick={close}
										class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-6 py-3 font-bold text-white transition-all hover:bg-gray-800"
									>
										Awesome!
									</button>
								{/if}
							{:else}
								<button
									onclick={close}
									class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black bg-black px-6 py-3 font-bold text-white transition-all hover:bg-gray-800"
								>
									Awesome!
								</button>
							{/if}
						{/if}
					</div>
				{/key}
			{/if}
		</div>
	</div>
{/if}
