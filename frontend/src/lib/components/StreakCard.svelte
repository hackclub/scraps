<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { API_URL } from '$lib/config';
	import {
		Flame,
		Check,
		ChevronLeft,
		ChevronRight,
		Spool,
		Dices,
		Trophy,
		Ticket,
		X
	} from '@lucide/svelte';

	type RewardState = 'claimable' | 'claimed' | 'upcoming' | 'lost' | 'expired';
	type Reward = {
		kind: 'spool' | 'roll' | 'week' | 'ticket';
		title: string;
		tickets: number;
		scraps?: number;
		state: RewardState;
		claimed?: string | null;
		pending: string[];
		slots: { slot: 'base' | 'bonus' | 'big'; kind: Reward['kind']; state: RewardState }[];
	};
	type StreakDay = {
		date: string;
		active: boolean;
		minutes: number;
		kept: boolean;
		reward: Reward | null;
	};
	type Streak = {
		today: string;
		goalMinutes: number;
		bonusMinutes: number;
		todayMinutes: number;
		weekStreak: number;
		weekDays: number;
		alive: boolean;
		tickets: number;
		weeks: StreakDay[][];
		unclaimed: string[];
	};
	type ShopItem = { id: number; name: string; image: string };

	const meta = {
		spool: { icon: Spool, label: 'shop slot item of your choice' },
		roll: { icon: Dices, label: 'random amount of scraps' },
		week: { icon: Trophy, label: '+100 scraps' },
		ticket: { icon: Ticket, label: 'raffle ticket' }
	};

	const hypeLines = [
		'keep it up',
		"you've got this",
		'lock in',
		'one more commit',
		'ship something today',
		'the streak believes in you',
		"don't break the chain",
		'future you says thanks',
		'small steps count',
		'touch keyboard, not grass'
	];
	const hype = hypeLines[Math.floor(Math.random() * hypeLines.length)];

	let { demo = false }: { demo?: boolean } = $props();

	let real = $state<Streak | null>(null);
	let loadError = $state<string | null>(null);

	const REWARDS_START = '2026-11-17';
	const GOAL = 30;
	const BONUS = 60;
	const HOUR_EVERY_DAY_START = '2026-11-23';
	type Big = { kind: Reward['kind']; tickets: number; scraps?: number };
	const SPOOL: Big = { kind: 'spool', tickets: 1 };
	const ROLL: Big = { kind: 'roll', tickets: 2 };
	const WEEK: Big = { kind: 'week', tickets: 3, scraps: 100 };
	const LEGACY_BIG: Record<number, Big> = { 2: SPOOL, 5: ROLL, 7: WEEK };
	const BIG: Record<number, Big> = { 3: SPOOL, 6: ROLL, 7: WEEK };
	const ROLL_ODDS: [number, number][] = [
		[10, 60],
		[25, 30],
		[50, 10]
	];

	type Sim = {
		today: string;
		minutes: Record<string, number>;
		claims: Record<string, Record<string, string>>;
		tickets: number;
	};
	type Part = { kind: string; tickets: number; scraps?: number };
	let sim = $state<Sim | null>(null);

	function addDays(s: string, n: number) {
		const [y, m, d] = s.split('-').map(Number);
		return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
	}
	function cwday(s: string) {
		const [y, m, d] = s.split('-').map(Number);
		return ((new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7) + 1;
	}
	function mondayOf(s: string) {
		return addDays(s, 1 - cwday(s));
	}
	function diffDays(a: string, b: string) {
		return Math.round((Date.parse(a) - Date.parse(b)) / 86400000);
	}
	function weekStartOf(s: string) {
		const m = mondayOf(s);
		return m > REWARDS_START ? m : REWARDS_START;
	}
	function hourEveryDay(d: string) {
		return d >= HOUR_EVERY_DAY_START;
	}
	function bigFor(d: string): Big | undefined {
		return (hourEveryDay(d) ? BIG : LEGACY_BIG)[cwday(d)];
	}
	function needsStreak(d: string, big: Big) {
		return !hourEveryDay(d) || big.kind === 'week';
	}

	function simState(sm: Sim): Streak {
		const t = sm.today;
		const mins = (d: string) => sm.minutes[d] ?? 0;
		const run = (d: string) => {
			let n = 0;
			for (let x = weekStartOf(d); x <= d; x = addDays(x, 1)) {
				if (mins(x) < GOAL) break;
				n++;
			}
			return n;
		};
		const ws = weekStartOf(t);
		const alive = t === ws || run(addDays(t, -1)) >= diffDays(t, ws);
		const parts = (d: string): Part[] => {
			if (d > t) return [];
			const big = bigFor(d);
			const out: Part[] = [];
			if (mins(d) >= GOAL) out.push({ kind: 'base', tickets: 1 });
			if (mins(d) >= BONUS) {
				if (!big || hourEveryDay(d)) out.push({ kind: 'hour', tickets: 1 });
				if (big && (!needsStreak(d, big) || run(d) >= diffDays(d, weekStartOf(d)) + 1))
					out.push(big);
			}
			return out;
		};
		const rewardFor = (d: string): Reward | null => {
			if (d < REWARDS_START) return null;
			const big = bigFor(d);
			const kind = big?.kind ?? 'ticket';
			const done = sm.claims[d] ?? {};
			const unlocked = parts(d);
			const pending = unlocked.filter((p) => !(p.kind in done));
			const inWindow = d >= addDays(mondayOf(t), -7);
			const slotState = (k: string, possible: boolean): RewardState => {
				if (k in done) return 'claimed';
				if (unlocked.some((p) => p.kind === k)) return inWindow ? 'claimable' : 'expired';
				if (d >= t) return possible ? 'upcoming' : 'lost';
				return 'lost';
			};
			const info = {
				kind,
				title: meta[kind].label,
				claimed: Object.values(done).join(', ') || null,
				pending: pending.map((p) => p.kind),
				tickets: pending.reduce((a, p) => a + p.tickets, 0),
				slots: [
					{ slot: 'base' as const, kind: 'ticket' as const, state: slotState('base', true) },
					...(!big || hourEveryDay(d)
						? [{ slot: 'bonus' as const, kind: 'ticket' as const, state: slotState('hour', true) }]
						: []),
					...(big
						? [
								{
									slot: 'big' as const,
									kind: big.kind,
									state: slotState(
										big.kind,
										!needsStreak(d, big) || mondayOf(d) > mondayOf(t) || alive
									)
								}
							]
						: [])
				]
			};
			const anyDone = Object.keys(done).length > 0;
			if (pending.length) {
				if (d >= addDays(mondayOf(t), -7)) return { ...info, state: 'claimable' };
				return { ...info, state: anyDone ? 'claimed' : 'expired' };
			}
			if (anyDone) return { ...info, state: 'claimed' };
			if (d >= t) {
				if (!big || hourEveryDay(d) || mondayOf(d) > mondayOf(t))
					return { ...info, state: 'upcoming' };
				return { ...info, state: alive ? 'upcoming' : 'lost' };
			}
			return { ...info, state: 'lost' };
		};
		const start = mondayOf(REWARDS_START);
		const count = diffDays(mondayOf(t), start) / 7 + 1;
		const wks: StreakDay[][] = Array.from({ length: count }, (_, w) =>
			Array.from({ length: 7 }, (_, i) => {
				const d = addDays(start, w * 7 + i);
				const active = d >= REWARDS_START;
				return {
					date: d,
					active,
					minutes: mins(d),
					kept: active && mins(d) >= GOAL,
					reward: rewardFor(d)
				};
			})
		);
		return {
			today: t,
			goalMinutes: GOAL,
			bonusMinutes: BONUS,
			todayMinutes: mins(t),
			weekStreak: run(t),
			weekDays: 7 - diffDays(ws, mondayOf(t)),
			alive,
			tickets: sm.tickets,
			weeks: wks,
			unclaimed: wks
				.flat()
				.filter((x) => x.reward?.state === 'claimable')
				.map((x) => x.date)
		};
	}

	function simClaim(day: string, itemId?: number) {
		if (!sim) return null;
		const rw = simState(sim)
			.weeks.flat()
			.find((x) => x.date === day)?.reward;
		if (!rw || rw.state !== 'claimable') {
			claimError = 'nothing to claim for that day';
			return null;
		}
		const done = { ...(sim.claims[day] ?? {}) };
		let main: string | null = null;
		for (const k of rw.pending) {
			if (k === 'spool') {
				const item = spoolItems.find((i) => i.id === itemId);
				if (!item) {
					claimError = 'pick an item from the shop';
					return null;
				}
				main = done[k] = item.name;
			} else if (k === 'roll') {
				let pick = Math.random() * 100;
				const amount = ROLL_ODDS.find(([, w]) => (pick -= w) < 0)?.[0] ?? 10;
				main = done[k] = `+${amount} scraps`;
			} else if (k === 'week') {
				main = done[k] = '+100 scraps';
			} else {
				done[k] = 'raffle ticket';
			}
		}
		sim = { ...sim, claims: { ...sim.claims, [day]: done }, tickets: sim.tickets + rw.tickets };
		return main ?? 'raffle ticket';
	}

	function simStart(): Sim {
		const base = real?.today ?? REWARDS_START;
		return { today: weekStartOf(base), minutes: {}, claims: {}, tickets: real?.tickets ?? 0 };
	}

	async function simRefocus() {
		await tick();
		if (scroller) {
			visibleWeek = todayWeek;
			scroller.scrollLeft = todayWeek * scroller.clientWidth;
		}
	}

	function simAdd() {
		const sm = sim ?? simStart();
		sim = { ...sm, minutes: { ...sm.minutes, [sm.today]: (sm.minutes[sm.today] ?? 0) + 15 } };
		simRefocus();
	}

	function simNextDay() {
		const sm = sim ?? simStart();
		sim = { ...sm, today: addDays(sm.today, 1) };
		simRefocus();
	}

	function simReset() {
		sim = simStart();
		claiming = null;
		simRefocus();
	}

	function simExit() {
		sim = null;
		claiming = null;
		simRefocus();
	}

	function easternToday() {
		return new Intl.DateTimeFormat('en-CA', {
			timeZone: 'America/New_York',
			year: 'numeric',
			month: '2-digit',
			day: '2-digit'
		}).format(new Date());
	}

	function blankStreak(): Streak {
		const today = easternToday();
		const st = simState({
			today: today < REWARDS_START ? REWARDS_START : today,
			minutes: {},
			claims: {},
			tickets: 0
		});
		return {
			...st,
			weeks: st.weeks.map((w) =>
				w.map((d) => ({
					...d,
					reward: d.reward && {
						...d.reward,
						state: 'upcoming',
						slots: d.reward.slots.map((x) => ({ ...x, state: 'upcoming' as const }))
					}
				}))
			)
		};
	}

	const placeholder = blankStreak();
	let loading = $derived(!sim && !real);
	let streak = $derived(sim ? simState(sim) : (real ?? placeholder));

	async function loadStreak() {
		try {
			const res = await fetch(`${API_URL}/streak`, { credentials: 'include' });
			if (!res.ok) throw new Error(`couldn't load your streak (${res.status})`);
			real = await res.json();
			loadError = null;
		} catch (e) {
			loadError = e instanceof Error ? e.message : "couldn't load your streak";
		}
	}

	function parseDay(s: string) {
		const [y, m, d] = s.split('-').map(Number);
		return new Date(y, m - 1, d);
	}

	function shortDate(s: string) {
		return parseDay(s)
			.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
			.toLowerCase();
	}

	let weeks = $derived(streak?.weeks ?? []);
	let todayWeek = $derived(Math.max(weeks.length - 1, 0));
	let todayMinutes = $derived(streak?.todayMinutes ?? 0);
	let goal = $derived(streak?.goalMinutes ?? 30);
	let bonus = $derived(streak?.bonusMinutes ?? 60);
	let left = $derived(Math.max(goal - todayMinutes, 0));
	let done = $derived(left === 0);
	let bonusLeft = $derived(Math.max(bonus - todayMinutes, 0));
	const R = 18;
	const C = 2 * Math.PI * R;
	let dash = $derived(C * Math.min(todayMinutes / bonus, 1));

	function isFuture(d: StreakDay) {
		return !!streak && d.date > streak.today;
	}

	let claiming = $state<{ day: StreakDay; reward: Reward } | null>(null);
	let busy = $state(false);
	let rolling = $state(false);
	let rollShown = $state<string | null>(null);
	let justClaimed = $state<string | null>(null);
	let claimError = $state<string | null>(null);
	let spoolItems = $state<ShopItem[]>([]);
	let retained = $state<{ cap: number; used: number; items: ShopItem[] } | null>(null);
	let spoolChoice = $state<number | null>(null);
	let spoolFull = $derived(!!retained && retained.used >= retained.cap);
	let retainedIds = $derived(new Set(retained?.items.map((i) => i.id) ?? []));

	async function loadSpool() {
		const [itemsRes, retainedRes] = await Promise.all([
			fetch(`${API_URL}/shop/items`, { credentials: 'include' }),
			fetch(`${API_URL}/shop/retained`, { credentials: 'include' })
		]);
		if (itemsRes.ok) spoolItems = await itemsRes.json();
		if (retainedRes.ok) retained = await retainedRes.json();
	}

	async function removeRetained(id: number) {
		busy = true;
		claimError = null;
		try {
			const res = await fetch(`${API_URL}/shop/retained/${id}`, {
				method: 'DELETE',
				credentials: 'include'
			});
			if (!res.ok) claimError = "couldn't remove that item";
			await loadSpool();
		} finally {
			busy = false;
		}
	}

	function flowOf(rw: Reward) {
		return (rw.pending.find((k) => k === 'spool' || k === 'roll' || k === 'week') ??
			'ticket') as Reward['kind'];
	}

	function openClaim(day: StreakDay, reward: Reward) {
		tip = null;
		claiming = { day, reward };
		rollShown = null;
		rolling = false;
		justClaimed = null;
		claimError = null;
		spoolChoice = null;
		if (flowOf(reward) === 'spool') {
			if (sim) {
				retained = null;
				fetch(`${API_URL}/shop/items`, { credentials: 'include' }).then(async (r) => {
					if (r.ok) spoolItems = await r.json();
				});
			} else loadSpool();
		}
	}

	async function claim(itemId?: number) {
		if (!claiming) return null;
		if (sim) {
			claimError = null;
			return simClaim(claiming.day.date, itemId);
		}
		busy = true;
		claimError = null;
		try {
			const res = await fetch(`${API_URL}/streak/claim`, {
				method: 'POST',
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ date: claiming.day.date, itemId })
			});
			const data = await res.json();
			if (!res.ok) {
				claimError = data.error ?? "couldn't claim that";
				return null;
			}
			const { success: _s, detail, tickets: _t, ...next } = data;
			real = next;
			return detail as string;
		} catch {
			claimError = "couldn't claim that";
			return null;
		} finally {
			busy = false;
		}
	}

	async function claimSimple() {
		const detail = await claim();
		if (detail) justClaimed = detail;
	}

	async function claimSpool() {
		if (spoolChoice === null) return;
		const detail = await claim(spoolChoice);
		if (detail) justClaimed = detail;
	}

	async function roll() {
		rolling = true;
		const faces = ['10 scraps', '25 scraps', '50 scraps'];
		let n = 0;
		const id = setInterval(() => {
			rollShown = faces[n++ % faces.length];
		}, 90);
		const [detail] = await Promise.all([claim(), new Promise((r) => setTimeout(r, 1100))]);
		clearInterval(id);
		rolling = false;
		rollShown = detail ? detail.replace('+', '') : null;
		if (detail) justClaimed = detail;
	}

	let tip = $state<{ x: number; y: number; hour: boolean; big: string | null } | null>(null);

	function showTip(e: Event, rw: Reward) {
		const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
		const half = 112;
		tip = {
			x: Math.min(Math.max(r.left + r.width / 2, half + 8), window.innerWidth - half - 8),
			y: r.top,
			hour: rw.slots.some((s) => s.slot === 'bonus'),
			big: rw.slots.find((s) => s.slot === 'big') ? meta[rw.kind].label : null
		};
	}

	let scroller = $state<HTMLDivElement>() as HTMLDivElement;
	let visibleWeek = $state(0);
	let drag: { x: number; left: number } | null = null;

	function goWeek(i: number) {
		const w = Math.max(0, Math.min(weeks.length - 1, i));
		scroller.scrollTo({ left: w * scroller.clientWidth, behavior: 'smooth' });
	}

	function onScroll() {
		tip = null;
		visibleWeek = Math.round(scroller.scrollLeft / scroller.clientWidth);
	}

	function onPointerDown(e: PointerEvent) {
		if (e.pointerType !== 'mouse') return;
		drag = { x: e.clientX, left: scroller.scrollLeft };
		scroller.style.scrollSnapType = 'none';
	}

	function onPointerMove(e: PointerEvent) {
		if (!drag) return;
		scroller.scrollLeft = drag.left - (e.clientX - drag.x);
	}

	function onPointerUp() {
		if (!drag) return;
		drag = null;
		scroller.style.scrollSnapType = '';
		goWeek(Math.round(scroller.scrollLeft / scroller.clientWidth));
	}

	function weekLabel(week: StreakDay[]) {
		return `${shortDate((week.find((d) => d.active) ?? week[0]).date)} – ${shortDate(week[6].date)}`;
	}

	function dayClass(d: StreakDay) {
		if (isFuture(d) || !d.active) return 'border-dashed border-gray-300 text-gray-300';
		if (d.kept) return 'border-black bg-black text-white';
		if (streak && d.date === streak.today) return 'border-black border-dashed';
		return 'border-gray-300 text-gray-400';
	}

	function badgeClass(state: RewardState) {
		if (state === 'claimable')
			return 'cursor-pointer bg-black text-white ring-2 ring-white animate-pulse hover:animate-none hover:scale-110';
		if (state === 'claimed') return 'bg-black text-white ring-2 ring-white';
		if (state === 'upcoming') return 'border-2 border-black bg-white text-black';
		return 'border-2 border-dashed border-gray-300 bg-white text-gray-300';
	}

	onMount(async () => {
		if (scroller) {
			visibleWeek = todayWeek;
			scroller.scrollLeft = todayWeek * scroller.clientWidth;
		}
		await loadStreak();
		await tick();
		if (scroller && visibleWeek !== todayWeek) {
			visibleWeek = todayWeek;
			scroller.scrollLeft = todayWeek * scroller.clientWidth;
		}
	});
</script>

{#if demo}
	<p class="mb-2 text-xs text-gray-400">
		{#if sim}
			<span class="font-bold text-black">simulating</span> · nothing is saved ·
		{:else}
			streak is your real data ·
		{/if}
		<button onclick={simAdd} class="cursor-pointer underline">+15 min</button>
		·
		<button onclick={simNextDay} class="cursor-pointer underline">next day</button>
		·
		<button onclick={simReset} class="cursor-pointer underline">reset to start of week</button>
		{#if sim}
			·
			<button onclick={simExit} class="cursor-pointer underline">back to real data</button>
		{/if}
	</p>
{/if}

<div class="rounded-2xl border-4 border-black p-4 md:p-6">
	{#if loadError && loading}
		<p class="mb-3 text-sm text-gray-500">
			{loadError} ·
			<button onclick={loadStreak} class="cursor-pointer underline">retry</button>
		</p>
	{/if}
	<div class="grid gap-6 md:grid-cols-[16rem_minmax(0,1fr)]">
		<div class="flex flex-col">
			<div class="flex items-center gap-3">
				<div class="relative h-12 w-12 shrink-0" title="{todayMinutes} min coded today">
					<svg viewBox="0 0 44 44" class="h-12 w-12 -rotate-90">
						<circle cx="22" cy="22" r={R} fill="none" stroke="#e5e7eb" stroke-width="5" />
						<circle
							cx="22"
							cy="22"
							r={R}
							fill="none"
							stroke="#000"
							stroke-width="5"
							stroke-linecap="round"
							stroke-dasharray="{dash} {C}"
							class="transition-all duration-300"
						/>
					</svg>
					<span class="absolute inset-0 flex items-center justify-center text-xs font-bold">
						{#if bonusLeft === 0}<Check size={16} />{:else if !done}{left}m{:else}{bonusLeft}m{/if}
					</span>
				</div>
				<div class="min-w-0">
					<p class="flex items-center gap-1 font-bold">
						<Flame size={16} />
						{streak.weekStreak}/{streak.weekDays} this week
					</p>
					<p class="text-sm text-gray-600">{hype}</p>
				</div>
			</div>

			<div class="mt-3 flex items-center gap-2">
				<span
					class="inline-flex items-center gap-1 rounded-full border-2 border-black px-2 py-0.5 text-sm font-bold"
					title="raffle tickets"
				>
					<Ticket size={14} />
					{#if loading}raffle tickets{:else}you have {streak.tickets} raffle {streak.tickets === 1
							? 'ticket'
							: 'tickets'}{/if}
				</span>
			</div>
			<a
				href="/raffle"
				class="mt-2 inline-flex items-center justify-center gap-1 rounded-full border-2 border-black bg-black px-3 py-1 text-sm font-bold text-white transition-all hover:bg-gray-800"
			>
				choose where to raffle!
			</a>
		</div>

		<div class="min-w-0">
			<div class="mb-2 flex items-center justify-between">
				<p class="text-xs font-bold text-gray-500">
					{visibleWeek === todayWeek
						? `this week (${weekLabel(weeks[visibleWeek])})`
						: weekLabel(weeks[visibleWeek])}
				</p>
				<div class="flex items-center gap-1">
					<button
						onclick={() => goWeek(visibleWeek - 1)}
						disabled={visibleWeek === 0}
						aria-label="previous week"
						class="cursor-pointer rounded-full border-2 border-black p-0.5 disabled:cursor-not-allowed disabled:border-gray-300 disabled:text-gray-300"
						><ChevronLeft size={14} /></button
					>
					<button
						onclick={() => goWeek(visibleWeek + 1)}
						disabled={visibleWeek === weeks.length - 1}
						aria-label="next week"
						class="cursor-pointer rounded-full border-2 border-black p-0.5 disabled:cursor-not-allowed disabled:border-gray-300 disabled:text-gray-300"
						><ChevronRight size={14} /></button
					>
				</div>
			</div>

			<div
				bind:this={scroller}
				role="region"
				aria-label="weekly streak calendar"
				onscroll={onScroll}
				onpointerdown={onPointerDown}
				onpointermove={onPointerMove}
				onpointerup={onPointerUp}
				onpointerleave={onPointerUp}
				class="no-scrollbar flex cursor-grab snap-x snap-mandatory overflow-x-auto select-none active:cursor-grabbing"
			>
				{#each weeks as week, w (w)}
					<div class="grid w-full shrink-0 snap-start grid-cols-7 gap-1.5 md:gap-2">
						{#each week as day (day.date)}
							{@const rw = day.reward}
							{@const d = parseDay(day.date)}
							{@const canClaim = rw?.state === 'claimable'}
							<div
								role="button"
								tabindex={canClaim ? 0 : -1}
								aria-disabled={!canClaim}
								aria-label={canClaim ? `claim ${shortDate(day.date)}` : shortDate(day.date)}
								onclick={() => canClaim && rw && openClaim(day, rw)}
								onkeydown={(e) =>
									canClaim && rw && (e.key === 'Enter' || e.key === ' ') && openClaim(day, rw)}
								class="flex flex-col items-center rounded-xl border-2 px-1 py-2 transition-colors duration-300 {canClaim
									? 'cursor-pointer hover:scale-105'
									: ''} {dayClass(day)}"
							>
								<span class="text-xs"
									>{d.toLocaleDateString('en-US', { weekday: 'short' }).toLowerCase()}</span
								>
								<span class="text-lg font-bold">{d.getDate()}</span>
								<span class="h-4 text-xs opacity-70">
									{#if !loading && !isFuture(day) && day.active}{day.minutes}m{/if}
								</span>
								<span
									class="mt-1 flex flex-col items-center justify-center gap-1 sm:h-7 sm:flex-row"
								>
									{#if rw}
										{#each rw.slots as sl (sl.slot)}
											{@const Icon = meta[sl.kind].icon}
											<button
												onclick={(e) => {
													e.stopPropagation();
													if (rw.state === 'claimable') openClaim(day, rw);
													else if (tip) tip = null;
													else showTip(e, rw);
												}}
												onmouseenter={(e) => showTip(e, rw)}
												onmouseleave={() => (tip = null)}
												onfocus={(e) => showTip(e, rw)}
												onblur={() => (tip = null)}
												aria-label={sl.slot === 'base'
													? '30 min: raffle ticket'
													: sl.slot === 'bonus'
														? '1 hour: raffle ticket'
														: `1 hour bonus: ${meta[sl.kind].label}`}
												class="relative flex {sl.slot === 'base'
													? 'h-5 w-5'
													: 'h-6 w-6'} items-center justify-center rounded-full transition-transform {badgeClass(
													sl.state
												)}"
											>
												<Icon size={sl.slot === 'base' ? 10 : 12} />
												{#if sl.state === 'claimed'}
													<span
														class="absolute -right-1 -bottom-1 flex h-3 w-3 items-center justify-center rounded-full border border-black bg-white text-black"
														><Check size={8} /></span
													>
												{/if}
											</button>
										{/each}
									{/if}
								</span>
							</div>
						{/each}
					</div>
				{/each}
			</div>
		</div>
	</div>
</div>

{#if tip}
	<div
		class="pointer-events-none fixed z-40 w-56 -translate-x-1/2 -translate-y-full rounded-xl border-2 border-black bg-white px-3 py-2 text-xs shadow-[3px_3px_0_0_#000]"
		style="left: {tip.x}px; top: {tip.y - 8}px"
		role="tooltip"
	>
		<p class="text-gray-700"><span class="font-bold">30 min:</span> raffle ticket</p>
		{#if tip.hour}
			<p class="text-gray-700"><span class="font-bold">1 hour:</span> raffle ticket</p>
		{/if}
		{#if tip.big}
			<p class="text-gray-700">
				<span class="font-bold">bonus:</span>
				{tip.big}
			</p>
		{/if}
	</div>
{/if}

{#if claiming}
	{@const kind = flowOf(claiming.reward)}
	{@const Icon = meta[kind].icon}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		role="presentation"
		onclick={(e) => e.target === e.currentTarget && !rolling && !busy && (claiming = null)}
	>
		<div
			class="relative flex max-h-[90vh] w-full max-w-md flex-col rounded-2xl border-4 border-black bg-white p-6"
		>
			<button
				onclick={() => (claiming = null)}
				disabled={rolling || busy}
				aria-label="close"
				class="absolute top-4 right-4 cursor-pointer"><X size={20} /></button
			>
			<div class="mb-4 flex items-center gap-3">
				<span class="flex h-12 w-12 items-center justify-center rounded-full bg-black text-white"
					><Icon size={24} /></span
				>
				<div>
					<h2 class="text-xl font-bold">
						{kind === 'ticket' ? 'raffle ticket' : claiming.reward.title}
					</h2>
					<p class="text-sm text-gray-600">
						{kind === 'ticket' ? 'daily ticket' : 'bonus'} · {shortDate(claiming.day.date)}
					</p>
				</div>
			</div>

			{#if justClaimed}
				<div class="rounded-xl border-4 border-black p-4 text-center">
					<p class="text-sm text-gray-600">you got</p>
					<p class="text-2xl font-bold">{justClaimed}</p>
					<p class="mt-2 inline-flex items-center gap-1 text-sm font-bold">
						<Ticket size={14} /> +{claiming.reward.tickets} raffle ticket{claiming.reward
							.tickets === 1
							? ''
							: 's'}
					</p>
				</div>
				<button
					onclick={() => (claiming = null)}
					class="mt-4 w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800"
					>nice</button
				>
			{:else if kind === 'ticket'}
				<p class="mb-3 text-sm">
					{claiming.reward.pending.includes('base') && claiming.reward.pending.includes('hour')
						? 'you coded an hour. here are your tickets.'
						: claiming.reward.pending.includes('base')
							? "you coded 30 min. here's a ticket."
							: "you hit 1 hour. here's another ticket."}
				</p>
				<div class="rounded-xl border-4 border-black p-4 text-center">
					<p class="flex items-center justify-center gap-2 text-3xl font-bold">
						<Ticket size={28} /> +{claiming.reward.tickets}
					</p>
				</div>
				<button
					onclick={claimSimple}
					disabled={busy}
					class="mt-4 w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
					>claim</button
				>
			{:else if kind === 'spool'}
				{#if spoolFull && retained}
					<p class="mb-2 text-sm">
						your shop is full ({retained.used}/{retained.cap}). remove an item first, then pick a
						new one.
					</p>
					<div class="mb-3 flex flex-col gap-2">
						{#each retained.items as item (item.id)}
							<div
								class="flex items-center justify-between rounded-xl border-2 border-black px-3 py-2 text-sm"
							>
								<span class="truncate font-bold">{item.name}</span>
								<button
									onclick={() => removeRetained(item.id)}
									disabled={busy}
									class="cursor-pointer rounded-full border-2 border-black px-2 py-0.5 text-xs font-bold hover:bg-gray-100 disabled:opacity-50"
									>remove</button
								>
							</div>
						{/each}
					</div>
				{:else}
					<p class="mb-3 text-sm">
						pick one item to keep in your shop{retained
							? ` (${retained.used}/${retained.cap} used)`
							: ''}:
					</p>
					<div class="grid min-h-0 flex-1 grid-cols-2 gap-2 overflow-y-auto">
						{#each spoolItems.filter((i) => !retainedIds.has(i.id)) as item (item.id)}
							<button
								onclick={() => (spoolChoice = item.id)}
								class="flex cursor-pointer flex-col items-center gap-1 rounded-xl border-4 p-2 text-center text-sm font-bold transition-all {spoolChoice ===
								item.id
									? 'border-black bg-black text-white'
									: 'border-black hover:border-dashed'}"
							>
								{#if item.image}
									<img src={item.image} alt="" class="h-14 w-14 object-contain" />
								{/if}
								<span class="line-clamp-2">{item.name}</span>
							</button>
						{/each}
					</div>
					<p class="mt-3 flex items-center gap-1 text-sm text-gray-600">
						<Ticket size={14} /> + {claiming.reward.tickets} raffle {claiming.reward.tickets === 1
							? 'ticket'
							: 'tickets'}
					</p>
					<button
						onclick={claimSpool}
						disabled={spoolChoice === null || busy}
						class="mt-4 w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
						>claim</button
					>
				{/if}
			{:else if kind === 'roll'}
				<p class="mb-3 text-sm">one free roll for bonus scraps.</p>
				<div
					class="flex h-24 items-center justify-center rounded-xl border-4 border-dashed border-black text-xl font-bold"
				>
					{rollShown ?? '?'}
				</div>
				<p class="mt-3 flex items-center gap-1 text-sm text-gray-600">
					<Ticket size={14} /> + {claiming.reward.tickets} raffle {claiming.reward.tickets === 1
						? 'ticket'
						: 'tickets'}
				</p>
				<button
					onclick={roll}
					disabled={rolling || busy}
					class="mt-4 w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
					>{rolling ? 'rolling...' : 'roll'}</button
				>
			{:else}
				<p class="mb-3 text-sm">you coded every day this week. that's the big one.</p>
				<div class="rounded-xl border-4 border-black p-4 text-center">
					<p class="flex items-center justify-center gap-2 text-3xl font-bold">
						<Spool size={28} /> +100
					</p>
					<p class="mt-1 flex items-center justify-center gap-1 text-sm font-bold">
						<Ticket size={14} /> + {claiming.reward.tickets} raffle {claiming.reward.tickets === 1
							? 'ticket'
							: 'tickets'}
					</p>
				</div>
				<button
					onclick={claimSimple}
					disabled={busy}
					class="mt-4 w-full cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
					>claim</button
				>
			{/if}

			{#if claimError}
				<p class="mt-3 rounded-lg bg-red-50 p-2 text-sm text-red-600">{claimError}</p>
			{/if}
		</div>
	</div>
{/if}

<style>
	.no-scrollbar {
		scrollbar-width: none;
	}
	.no-scrollbar::-webkit-scrollbar {
		display: none;
	}
</style>
