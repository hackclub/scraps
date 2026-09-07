<script lang="ts">
	import { onMount, onDestroy, untrack } from 'svelte';
	import { fade } from 'svelte/transition';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import OnboardingPayout from './OnboardingPayout.svelte';
	import OnboardingGachapon from './OnboardingGachapon.svelte';
	import CreateProjectModal from './CreateProjectModal.svelte';
	import { addProject, type Project } from '$lib/stores';

	let { onComplete }: { onComplete: () => void } = $props();

	type Emotion = 'normal' | 'excited' | 'happy' | 'bored' | 'sadorcrying' | 'sus';

	type Panel = null | 'ship-form' | 'payout' | 'shop-pick' | 'gachapon';

	interface Beat {
		emotion: Emotion;
		text: string;
		sub?: string;
		panel?: Panel;
		highlight?: string;
		nav?: string;
		when?: () => boolean;
		waitFor?: 'project-created' | 'payout-resolved' | 'gachapon-pulled';
	}

	let showCreateModal = $state(false);
	let finalRollMult = $state<number | null>(null);
	let pickedShopItems = $state(0);

	const beats: Beat[] = [
		{
			emotion: 'normal',
			text: "Hi! Welcome to Scraps. I'm Scrappy :D",
			sub: '(yes, iamalive has terrible naming sense)'
		},
		{
			emotion: 'excited',
			text: 'Scraps is a Hack Club YSWS program where you ship projects and %%gamble%% roll for a chance at cool items: some straight from past events!'
		},
		{ emotion: 'normal', text: 'Let me walk you through the site.' },

		{
			emotion: 'normal',
			text: 'First up: projects. This is your dashboard, where they live. Hit **new project**: a name and a description is all you need to start.',
			nav: '/dashboard',
			highlight: 'button[data-tutorial="new-project"]',
			waitFor: 'project-created'
		},
		{
			emotion: 'normal',
			text: "But to **ship** it (that's how you turn hours into scraps) a few more fields need filling in first. The glowing ones here are required.",
			nav: '/dashboard',
			panel: 'ship-form'
		},
		{
			emotion: 'normal',
			text: 'Fill those, hit submit, and it goes into the review queue.',
			nav: '/dashboard'
		},

		{
			emotion: 'happy',
			text: "Once a reviewer approves it, you get scraps! Here's a real example: hit **check project** up top.",
			panel: 'payout'
		},
		{
			emotion: 'normal',
			text: "Your hours × a rate gives a base amount. The reviewer's score (1-3) scales it: 2 is neutral, 3 is a nice bump.",
			panel: 'payout'
		},
		{
			emotion: 'sus',
			text: 'Then there\'s a bonus roll: **lock it in**, or **reroll once** (binding) for a shot at higher... or lower.',
			panel: 'payout',
			waitFor: 'payout-resolved'
		},
		{
			emotion: 'happy',
			text: 'There you go: hours → score → roll. Whatever you land on becomes real scraps once approved.',
			when: () => finalRollMult !== null && finalRollMult >= 1
		},
		{
			emotion: 'sadorcrying',
			text: "Landed under ×1 this time. That's the risk with rerolling: it happens.",
			when: () => finalRollMult !== null && finalRollMult < 1
		},

		{
			emotion: 'normal',
			text: 'Onto the shop. Every day, **5 fresh items** rotate in. Right now you have **3 open slots**.',
			nav: '/shop'
		},
		{
			emotion: 'excited',
			text: "One-time thing, just for you: pick **any 2 items** from the whole shop so you can see everything that's up for grabs.",
			nav: '/shop',
			panel: 'shop-pick'
		},
		{
			emotion: 'happy',
			text: 'After that, you can drag items in and out of **your shop**. Whatever you keep there sticks around after the daily reset.',
			nav: '/shop'
		},

		{
			emotion: 'sus',
			text: 'The **refinery** lets you spend scraps to bump up your win odds on one specific item.',
			nav: '/refinery',
			highlight: 'a[href="/refinery"]'
		},

		{
			emotion: 'excited',
			text: '**Gachapons** are guaranteed pulls: pay a bit more, get one random item from a set, no losing.',
			nav: '/shop'
		},

		{
			emotion: 'excited',
			text: 'Thanks for finishing the tutorial! As a reward, try your luck at the gachapon: you can get **5**, **10**, **50** or **100** scraps!',
			nav: '/shop',
			panel: 'gachapon',
			waitFor: 'gachapon-pulled'
		},
		{
			emotion: 'happy',
			text: "And that's it. Go build something silly. 👋"
		}
	];

	let idx = $state(0);
	let visible = $derived(beats.filter((b) => !b.when || b.when()));

	function nextVisibleFrom(from: number): number {
		for (let i = from; i < beats.length; i++) {
			if (!beats[i].when || beats[i].when!()) return i;
		}
		return -1;
	}

	let beat = $derived(beats[idx]);

	type Run = { kind: 'plain' | 'b' | 's' | 'strike'; text: string };

	function parse(src: string): Run[] {
		const parsed: Run[] = [];
		const re = /(\*\*[^*]+\*\*|~~[^~]+~~|%%[^%]+%%)/g;
		let last = 0;
		let m: RegExpExecArray | null;
		while ((m = re.exec(src))) {
			if (m.index > last) parsed.push({ kind: 'plain', text: src.slice(last, m.index) });
			const tok = m[0];
			if (tok.startsWith('**')) parsed.push({ kind: 'b', text: tok.slice(2, -2) });
			else if (tok.startsWith('~~')) parsed.push({ kind: 'strike', text: tok.slice(2, -2) });
			else parsed.push({ kind: 's', text: tok.slice(2, -2) });
			last = re.lastIndex;
		}
		if (last < src.length) parsed.push({ kind: 'plain', text: src.slice(last) });
		return parsed;
	}

	let runs = $derived(parse(beat.text));
	let fullLen = $derived(runs.reduce((n, r) => n + r.text.length, 0));
	let shown = $state(0);
	let typing = $state(false);
	let struck = $state(false);
	let timer: ReturnType<typeof setTimeout> | undefined;

	function clearTimer() {
		if (timer) clearTimeout(timer);
		timer = undefined;
	}

	function startTyping() {
		clearTimer();
		shown = 0;
		struck = false;
		typing = true;
		step();
	}

	function step() {
		if (shown >= fullLen) {
			typing = false;
			return;
		}
		shown++;
		let acc = 0;
		let pause = 22;
		for (const r of runs) {
			if (shown <= acc + r.text.length) {
				const ch = r.text[shown - acc - 1];
				if (r.kind === 's' && shown === acc + r.text.length) {
					struck = true;
					pause = 620;
				} else if (ch === ' ') pause = 34;
				else if (/[.,!?:]/.test(ch)) pause = 240;
				break;
			}
			acc += r.text.length;
		}
		timer = setTimeout(step, pause);
	}

	function runShown(rIndex: number): string {
		let acc = 0;
		for (let i = 0; i < rIndex; i++) acc += runs[i].text.length;
		return runs[rIndex].text.slice(0, Math.max(0, shown - acc));
	}

	function advance() {
		if (typing) {
			clearTimer();
			shown = fullLen;
			struck = runs.some((r) => r.kind === 's');
			typing = false;
			return;
		}
		if (beat.waitFor === 'project-created') {
			if (!showCreateModal) showCreateModal = true;
			return;
		}
		if (beat.waitFor === 'payout-resolved' || beat.waitFor === 'gachapon-pulled') return;
		const nxt = nextVisibleFrom(idx + 1);
		if (nxt === -1) {
			onComplete();
			return;
		}
		idx = nxt;
	}

	function onPayoutFinal(mult: number) {
		finalRollMult = mult;
		const nxt = nextVisibleFrom(idx + 1);
		if (nxt === -1) onComplete();
		else idx = nxt;
	}

	function onGachaponFinal(_reward: number) {
		const nxt = nextVisibleFrom(idx + 1);
		if (nxt === -1) onComplete();
		else idx = nxt;
	}

	$effect(() => {
		idx;
		untrack(() => startTyping());
	});

	let currentNav = $state('');

	$effect(() => {
		const target = beat.nav;
		if (!browser || !target || target === currentNav) return;
		currentNav = target;
		goto(target, { invalidateAll: false, noScroll: true }).catch(() => {});
	});

	let hlTick = $state(0);
	let hlRect = $derived.by((): DOMRect | null => {
		hlTick;
		if (typeof document === 'undefined' || !beat.highlight) return null;
		const el = document.querySelector(beat.highlight);
		return el ? el.getBoundingClientRect() : null;
	});

	$effect(() => {
		if (!beat.highlight) return;
		beat.nav;
		let tries = 0;
		const tick = () => {
			hlTick++;
			if (++tries < 8 && !document.querySelector(beat.highlight ?? '')) {
				timers.push(setTimeout(tick, 150));
			}
		};
		const timers: ReturnType<typeof setTimeout>[] = [setTimeout(tick, 120)];
		const onResize = () => hlTick++;
		window.addEventListener('resize', onResize);
		return () => {
			timers.forEach(clearTimeout);
			window.removeEventListener('resize', onResize);
		};
	});

	function onProjectCreated(project: Project) {
		showCreateModal = false;
		addProject(project);
		const nxt = nextVisibleFrom(idx + 1);
		if (nxt === -1) onComplete();
		else idx = nxt;
	}

	function onKey(e: KeyboardEvent) {
		const target = e.target as HTMLElement | null;
		if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable)) {
			return;
		}
		if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowRight') {
			e.preventDefault();
			advance();
		}
	}

	onMount(() => {
		document.body.style.overflow = 'hidden';
	});
	onDestroy(() => {
		clearTimer();
		if (typeof document !== 'undefined') document.body.style.overflow = '';
	});

	let estimate = $derived.by(() => {
		let secs = 0;
		for (const b of beats) {
			secs += 1.4 + parse(b.text).reduce((n, r) => n + r.text.length, 0) / 28;
			if (b.waitFor) secs += 6;
			if (b.panel) secs += 2;
		}
		return Math.round(secs / 6) / 10;
	});

	const shipFields = [
		{ label: 'project name', required: true },
		{ label: 'description', required: true },
		{ label: 'demo / repo link', required: true },
		{ label: 'hackatime project', required: true },
		{ label: 'screenshot', required: true },
		{ label: 'extra notes', required: false }
	];
	const shopMock = Array.from({ length: 9 }, (_, i) => i);

	let showPanel = $derived(beat.panel != null);
</script>

<svelte:window onkeydown={onKey} />

<CreateProjectModal
	open={showCreateModal}
	onClose={() => (showCreateModal = false)}
	onCreated={onProjectCreated}
/>

<div
	class="fixed inset-0 z-[90] {hlRect ? 'pointer-events-none' : ''}"
	transition:fade={{ duration: 150 }}
>
	<button
		onclick={onComplete}
		class="pointer-events-auto absolute top-4 right-4 z-20 cursor-pointer rounded-full border-2 border-white/60 bg-black/40 px-3 py-1 text-xs font-bold text-white transition-all hover:bg-black/70"
	>
		skip
	</button>

	{#if hlRect}
		<div class="pointer-events-auto absolute inset-0">
			<div
				class="absolute top-0 right-0 left-0 bg-black/70"
				style="height:{hlRect.top - 6}px"
			></div>
			<div
				class="absolute right-0 bottom-0 left-0 bg-black/70"
				style="top:{hlRect.top + hlRect.height + 6}px"
			></div>
			<div
				class="absolute bg-black/70"
				style="top:{hlRect.top - 6}px; left:0; width:{hlRect.left - 6}px; height:{hlRect.height +
					12}px"
			></div>
			<div
				class="absolute bg-black/70"
				style="top:{hlRect.top - 6}px; left:{hlRect.left +
					hlRect.width +
					6}px; right:0; height:{hlRect.height + 12}px"
			></div>
		</div>
		<div
			class="pointer-events-none absolute animate-pulse rounded-xl border-4 border-white"
			style="top:{hlRect.top - 6}px; left:{hlRect.left - 6}px; width:{hlRect.width +
				12}px; height:{hlRect.height + 12}px"
		></div>
	{:else}
		<div class="absolute inset-0 {beat.nav ? 'bg-black/35' : 'bg-black/70'}"></div>
	{/if}

	{#if showPanel}
		<div class="pointer-events-auto absolute top-20 left-1/2 -translate-x-1/2">
			{#if beat.panel === 'payout'}
				<OnboardingPayout onFinal={onPayoutFinal} />
			{:else if beat.panel === 'ship-form'}
				<div class="w-[min(92vw,30rem)] rounded-2xl border-4 border-black bg-white p-4 shadow-xl">
					<p class="mb-2 text-xs font-bold text-gray-500">SHIP CHECKLIST</p>
					<div class="grid gap-2 sm:grid-cols-2">
						{#each shipFields as f (f.label)}
							<div
								class="rounded-lg border-2 px-3 py-2 text-sm {f.required
									? 'animate-pulse border-yellow-500 bg-yellow-50 font-bold'
									: 'border-gray-300 text-gray-400'}"
							>
								{f.label}{f.required ? ' *' : ''}
							</div>
						{/each}
					</div>
				</div>
			{:else if beat.panel === 'shop-pick'}
				<div class="w-[min(92vw,26rem)] rounded-2xl border-4 border-black bg-white p-4 shadow-xl">
					<p class="mb-2 text-xs font-bold text-gray-500">
						PICK ANY 2 · {pickedShopItems}/2 chosen
					</p>
					<div class="grid grid-cols-3 gap-2">
						{#each shopMock as i (i)}
							<button
								onclick={() => (pickedShopItems = Math.min(2, pickedShopItems + 1))}
								class="flex aspect-square cursor-pointer items-center justify-center rounded-lg border-2 border-black text-lg transition-all hover:border-dashed"
							>
								🎁
							</button>
						{/each}
					</div>
				</div>
			{:else if beat.panel === 'gachapon'}
				<OnboardingGachapon onFinal={onGachaponFinal} />
			{/if}
		</div>
	{/if}

	<div
		class="pointer-events-auto absolute inset-x-0 bottom-0 flex justify-center px-4 pb-6"
		onclick={advance}
		onkeydown={onKey}
		role="button"
		tabindex="-1"
		aria-label="advance dialogue"
	>
		<div class="relative w-full max-w-2xl">
			<div
				class="pointer-events-none mx-auto mb-2 h-24 w-24 rounded-2xl border-4 border-black bg-white p-1 shadow-lg sm:hidden"
			>
				<img
					src="/images/scrappy/{beat.emotion}.png"
					alt="Scrappy"
					class="h-full w-full object-contain"
				/>
			</div>
			<div class="rounded-2xl border-4 border-black bg-white p-5 pt-4 shadow-2xl">
				<p class="mb-1 text-sm font-bold text-gray-500">Scrappy</p>
				<p class="min-h-[3.5rem] text-lg leading-snug">
					{#each runs as r, ri (ri)}
						{#if r.kind === 'b'}<strong>{runShown(ri)}</strong>{:else if r.kind === 'strike'}<span
								class="line-through">{runShown(ri)}</span
							>{:else if r.kind === 's'}<span class="strike" class:on={struck}>{runShown(ri)}</span
							>{:else}{runShown(ri)}{/if}
					{/each}<span class="caret" class:hidden={!typing}>▍</span>
				</p>
				{#if beat.sub && shown >= fullLen}
					<p class="mt-1 text-xs text-gray-400" transition:fade={{ duration: 150 }}>{beat.sub}</p>
				{/if}

				{#if beat.waitFor === 'project-created' && shown >= fullLen}
					<p class="mt-2 text-right text-xs font-bold text-yellow-600">
						{showCreateModal ? 'fill out the form to continue' : 'click or press enter to create a project'}
					</p>
				{:else if beat.waitFor === 'payout-resolved' && shown >= fullLen}
					<p class="mt-2 text-right text-xs font-bold text-yellow-600">
						roll it out above to continue
					</p>
				{:else if beat.waitFor === 'gachapon-pulled' && shown >= fullLen}
					<p class="mt-2 text-right text-xs font-bold text-yellow-600">
						pull the gachapon above to continue
					</p>
				{:else}
					<p class="mt-2 text-right text-xs text-gray-400">
						{typing ? 'click to skip' : 'click or press enter ▶'}
					</p>
				{/if}
			</div>

			<div
				class="pointer-events-none absolute right-full bottom-0 mr-3 hidden h-36 w-36 rounded-2xl border-4 border-black bg-white p-1 shadow-lg sm:block lg:h-48 lg:w-48"
			>
				<img
					src="/images/scrappy/{beat.emotion}.png"
					alt="Scrappy"
					class="h-full w-full object-contain"
				/>
			</div>

			<p class="mt-2 text-center text-[11px] text-gray-500">
				dev note: ~{estimate} min · beat {visible.indexOf(beat) + 1}/{visible.length}
			</p>
		</div>
	</div>
</div>

<style>
	.caret {
		animation: blink 1s steps(1) infinite;
	}
	@keyframes blink {
		50% {
			opacity: 0;
		}
	}

	.strike {
		position: relative;
	}
	.strike::after {
		content: '';
		position: absolute;
		left: 0;
		top: 50%;
		height: 3px;
		width: 0;
		background: #000;
		transition: width 0.35s ease;
	}
	.strike.on::after {
		width: 100%;
	}

	@media (prefers-reduced-motion: reduce) {
		.caret,
		.strike::after {
			animation: none;
			transition: none;
		}
		.strike.on::after {
			width: 100%;
		}
	}
</style>
