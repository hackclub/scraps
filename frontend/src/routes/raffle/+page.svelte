<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { ArrowLeft, Ticket, ImageIcon, Plus, Minus } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { getUser, requireLogin } from '$lib/auth-client';

	const FIRST_DRAW = new Date('2026-11-25T17:00:00Z');
	const DAY_MS = 24 * 60 * 60 * 1000;
	const WEEK_MS = 7 * DAY_MS;

	const weeks: { n: number; images: string[]; tbd: boolean }[] = [
		{
			n: 1,
			images: ['/raffle/week1-walkie-talkies.webp', '/raffle/week1-filament-dryer.webp'],
			tbd: false
		},
		{
			n: 2,
			images: [
				'/raffle/week2-exploding-kittens.webp',
				'/raffle/week2-mx-keys-mini.webp',
				'/raffle/week2-trex-costume.webp'
			],
			tbd: false
		},
		{ n: 3, images: [], tbd: true },
		{ n: 4, images: [], tbd: true }
	];

	function drawDate(n: number): Date {
		return new Date(FIRST_DRAW.getTime() + (n - 1) * WEEK_MS);
	}

	function shortDate(d: Date): string {
		return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
	}

	function weekRange(n: number): string {
		const draw = drawDate(n).getTime();
		return `${shortDate(new Date(draw - WEEK_MS))} – ${shortDate(new Date(draw - DAY_MS))}`;
	}

	function formatDraw(d: Date): string {
		return d.toLocaleString('en-US', {
			weekday: 'long',
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit',
			timeZone: 'America/New_York',
			timeZoneName: 'short'
		});
	}

	let now = $state(Date.now());
	let tickets = $state<number | null>(null);
	let placed = $state<Record<number, number>>({});
	let openWeeks = $state<number[]>([]);
	let error = $state<string | null>(null);
	let latest: Record<number, number> = {};
	let timer: ReturnType<typeof setInterval> | undefined;

	let placedTotal = $derived(Object.values(placed).reduce((a, b) => a + b, 0));
	let ticketsLeft = $derived(Math.max(0, (tickets ?? 0) - placedTotal));

	function canPlace(w: { n: number; tbd: boolean }): boolean {
		return !w.tbd && openWeeks.includes(w.n) && drawDate(w.n).getTime() > now;
	}

	function applyState(data: {
		tickets?: number;
		placed?: Record<string, number>;
		openWeeks?: number[];
	}) {
		tickets = data.tickets ?? 0;
		placed = Object.fromEntries(Object.entries(data.placed ?? {}).map(([k, v]) => [Number(k), v]));
		openWeeks = data.openWeeks ?? [];
	}

	async function loadRaffle() {
		const res = await fetch(`${API_URL}/raffle`, { credentials: 'include' });
		if (res.ok) applyState(await res.json());
	}

	async function save(n: number, count: number) {
		const id = (latest[n] ?? 0) + 1;
		latest[n] = id;
		error = null;
		try {
			const res = await fetch(`${API_URL}/raffle/${n}`, {
				method: 'PUT',
				credentials: 'include',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ tickets: count })
			});
			const data = await res.json();
			if (latest[n] !== id) return;
			if (!res.ok) {
				error = data.error ?? 'could not save your tickets';
				await loadRaffle();
				return;
			}
			applyState(data);
		} catch (e) {
			if (latest[n] !== id) return;
			error = 'could not save your tickets';
			console.error('Failed to save raffle tickets:', e);
			await loadRaffle();
		}
	}

	function add(n: number) {
		if (ticketsLeft <= 0) return;
		placed[n] = (placed[n] ?? 0) + 1;
		save(n, placed[n]);
	}

	function remove(n: number) {
		if (!placed[n]) return;
		placed[n] -= 1;
		save(n, placed[n]);
	}

	let nextWeek = $derived(weeks.find((w) => drawDate(w.n).getTime() > now) ?? null);
	let countdown = $derived.by(() => {
		if (!nextWeek) return null;
		const ms = Math.max(0, drawDate(nextWeek.n).getTime() - now);
		return {
			days: Math.floor(ms / 86_400_000),
			hours: Math.floor((ms % 86_400_000) / 3_600_000),
			minutes: Math.floor((ms % 3_600_000) / 60_000)
		};
	});

	onMount(async () => {
		timer = setInterval(() => (now = Date.now()), 1000);
		const user = await getUser();
		if (!user) {
			requireLogin();
			return;
		}
		try {
			await loadRaffle();
		} catch (e) {
			console.error('Failed to load raffle tickets:', e);
		}
	});

	onDestroy(() => clearInterval(timer));
</script>

<svelte:head>
	<title>raffle - scraps</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<a
		href="/dashboard"
		class="mb-8 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
	>
		<ArrowLeft size={20} />
		back to dashboard
	</a>

	<h1 class="mb-2 text-4xl font-bold md:text-5xl">
		how do you want to distribute your raffle tickets?
	</h1>
	<div
		class="mb-8 inline-flex items-center gap-2 rounded-full border-4 border-black px-4 py-2 text-lg font-bold"
	>
		<Ticket size={20} />
		{#if tickets === null}loading your tickets...{:else}{ticketsLeft} / {tickets} raffle {tickets ===
			1
				? 'ticket'
				: 'tickets'} left{/if}
	</div>
	{#if error}
		<p class="mb-6 font-bold text-red-600">{error}</p>
	{/if}

	<div
		class="mb-8 rounded-2xl border-4 border-black bg-white p-6 shadow-[6px_6px_0px_0px_rgba(0,0,0,1)]"
	>
		{#if nextWeek && countdown}
			<p class="mb-4 font-bold">
				week {nextWeek.n} ({weekRange(nextWeek.n)})'s reward will be drawn on {formatDraw(
					drawDate(nextWeek.n)
				)}
			</p>
			<div class="grid grid-cols-3 gap-3 text-center">
				<div class="rounded-xl border-4 border-black p-3">
					<p class="text-3xl font-bold md:text-4xl">{countdown.days}</p>
					<p class="text-sm text-gray-600">{countdown.days === 1 ? 'day' : 'days'}</p>
				</div>
				<div class="rounded-xl border-4 border-black p-3">
					<p class="text-3xl font-bold md:text-4xl">{countdown.hours}</p>
					<p class="text-sm text-gray-600">{countdown.hours === 1 ? 'hour' : 'hours'}</p>
				</div>
				<div class="rounded-xl border-4 border-black p-3">
					<p class="text-3xl font-bold md:text-4xl">{countdown.minutes}</p>
					<p class="text-sm text-gray-600">{countdown.minutes === 1 ? 'minute' : 'minutes'}</p>
				</div>
			</div>
		{:else}
			<p class="font-bold">all {weeks.length} weekly draws are done.</p>
		{/if}
	</div>

	<div class="grid gap-4 sm:grid-cols-2">
		{#each weeks as w (w.n)}
			{@const drawn = drawDate(w.n).getTime() <= now}
			<div
				class="relative overflow-hidden rounded-2xl border-4 border-black bg-white {drawn
					? 'opacity-50'
					: ''} {nextWeek?.n === w.n ? 'shadow-[6px_6px_0px_0px_rgba(0,0,0,1)]' : ''}"
			>
				{#if w.images.length > 0}
					<div
						class="flex aspect-video w-full items-center justify-center gap-3 border-b-4 border-black bg-gray-50 p-4"
					>
						{#each w.images as src (src)}
							<img
								{src}
								alt="week {w.n} reward"
								class="h-full min-w-0 flex-1 object-contain drop-shadow-md"
							/>
						{/each}
					</div>
				{:else}
					<div
						class="flex aspect-video w-full flex-col items-center justify-center gap-2 border-b-4 border-dashed border-black bg-gray-50 text-gray-400"
					>
						<ImageIcon size={32} />
						<span class="text-sm font-bold">week {w.n} image</span>
					</div>
				{/if}
				<div class="p-4">
					<p class="text-xl font-bold">
						week {w.n} <span class="text-base text-gray-600">({weekRange(w.n)})</span>
					</p>
					<p class="text-sm text-gray-600">
						{drawn ? 'drawn' : 'draw:'}
						{formatDraw(drawDate(w.n))}
					</p>
					<div class="mt-3 flex items-center gap-3">
						<button
							onclick={() => remove(w.n)}
							disabled={!canPlace(w) || !placed[w.n]}
							aria-label="remove a ticket from week {w.n}"
							class="flex h-9 w-9 cursor-pointer items-center justify-center rounded-full border-4 border-black transition-all hover:border-dashed disabled:cursor-not-allowed disabled:opacity-30"
						>
							<Minus size={16} />
						</button>
						<span class="flex min-w-12 items-center justify-center gap-1 text-xl font-bold">
							<Ticket size={18} />{placed[w.n] ?? 0}
						</span>
						<button
							onclick={() => add(w.n)}
							disabled={!canPlace(w) || ticketsLeft <= 0}
							aria-label="add a ticket to week {w.n}"
							class="flex h-9 w-9 cursor-pointer items-center justify-center rounded-full border-4 border-black bg-black text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-30"
						>
							<Plus size={16} />
						</button>
					</div>
				</div>
				{#if w.tbd}
					<div
						class="absolute inset-0 flex flex-col items-center justify-center bg-black/75 text-white"
					>
						<p class="text-4xl font-bold">TBD</p>
						<p class="text-sm font-bold">to be decided</p>
					</div>
				{/if}
			</div>
		{/each}
	</div>
</div>
