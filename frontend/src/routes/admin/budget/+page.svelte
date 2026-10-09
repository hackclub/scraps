<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { RefreshCw } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL, serverConfig } from '$lib/config';

	interface Route {
		route: string;
		orders: number;
		scrapsPaid: number;
		itemValueScraps: number;
		fulfillmentDollars: number;
	}

	interface Gachapon {
		id: number;
		name: string;
		price: number;
		expectedPrizeScraps: number;
		payoutRatio: number | null;
	}

	interface Budget {
		targetDollarsPerHour: [number, number];
		scrapsPerHour: number;
		scrapsPerDollar: number;
		approved: {
			projects: number;
			hours: number;
			scrapsAwarded: number;
			avgMultiplier: number | null;
			scoreDistribution: { score: number; count: number }[];
			payoutRollScraps: number;
		};
		payoutRoll: {
			expectedMultiplier: number;
			decided: number;
			rolled: number;
			undecided: number;
			realizedMultiplier: number | null;
		};
		bonusesScraps: number;
		queue: { projects: number; hours: number; projectedScraps: number; assumedMultiplier: number };
		committed: { scraps: number; dollars: number; perHour: number | null };
		projectedWithQueue: { dollars: number; perHour: number | null };
		spent: {
			scraps: number;
			refineryScraps: number;
			refineryUndoableScraps: number;
			unspentScraps: number;
		};
		delivered: {
			itemDollars: number;
			fulfillmentDollars: number;
			dollars: number;
			perHour: number | null;
		};
		routes: Route[];
		unclaimedConsolation: number;
		gachapons: Gachapon[];
	}

	let budget = $state<Budget | null>(null);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let whatIfScore = $state(2);

	onMount(async () => {
		const user = await getUser();
		if (!user || (user.role !== 'admin' && user.role !== 'creator')) {
			goto('/dashboard');
			return;
		}
		await load();
	});

	async function load() {
		loading = true;
		error = null;
		try {
			const res = await fetch(`${API_URL}/admin/budget`, { credentials: 'include' });
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			budget = await res.json();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load budget';
		} finally {
			loading = false;
		}
	}

	function scoreMultiplier(score: number): number {
		const y1 = serverConfig.reviewerScoreFloorMult ?? 0.5;
		const y2 = serverConfig.reviewerScoreNeutralMult ?? 1;
		const y3 = serverConfig.reviewerScoreCeilMult ?? 2;
		const s = Math.min(3, Math.max(1, score));
		const l1 = ((s - 2) * (s - 3)) / 2;
		const l2 = -(s - 1) * (s - 3);
		const l3 = ((s - 1) * (s - 2)) / 2;
		return y1 * l1 + y2 * l2 + y3 * l3;
	}

	let whatIf = $derived.by(() => {
		if (!budget) return null;
		const mult = scoreMultiplier(whatIfScore);
		const queueScraps =
			budget.queue.hours *
			budget.scrapsPerHour *
			mult *
			(budget.payoutRoll?.expectedMultiplier ?? 1);
		const scraps = budget.committed.scraps + queueScraps;
		const hours = budget.approved.hours + budget.queue.hours;
		const dollars = scraps / budget.scrapsPerDollar;
		return {
			mult,
			queueDollars: queueScraps / budget.scrapsPerDollar,
			perHour: hours > 0 ? dollars / hours : null
		};
	});

	function money(n: number | null | undefined) {
		return n == null
			? '—'
			: `$${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
	}

	function num(n: number | null | undefined) {
		return n == null ? '—' : n.toLocaleString();
	}

	function rateTone(rate: number | null | undefined) {
		if (rate == null || !budget) return 'border-black';
		const [lo, hi] = budget.targetDollarsPerHour;
		if (rate > hi) return 'border-red-600 bg-red-50';
		if (rate < lo) return 'border-yellow-500 bg-yellow-50';
		return 'border-green-600 bg-green-50';
	}

	function rateLabel(rate: number | null | undefined) {
		if (rate == null || !budget) return 'no approved hours yet';
		const [lo, hi] = budget.targetDollarsPerHour;
		if (rate > hi) return 'over target';
		if (rate < lo) return 'under target';
		return 'on target';
	}

	const ROUTE_LABELS: Record<string, string> = {
		purchase: 'direct purchase',
		luck_win: 'luck roll win',
		gachapon: 'gachapon',
		consolation: 'consolation prize',
		referral_reward: 'referral reward'
	};
</script>

<svelte:head>
	<title>budget - admin - scraps</title>
</svelte:head>

<div class="mx-auto max-w-5xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-2 flex items-center justify-between gap-4">
		<h1 class="text-4xl font-bold md:text-5xl">budget</h1>
		<button
			onclick={load}
			disabled={loading}
			class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-4 py-2 font-bold transition-all hover:border-dashed disabled:opacity-50"
		>
			<RefreshCw size={16} class={loading ? 'animate-spin' : ''} />
			refresh
		</button>
	</div>
	{#if budget}
		<p class="mb-8 text-gray-600">
			target: <strong
				>{money(budget.targetDollarsPerHour[0])}–{money(budget.targetDollarsPerHour[1])}</strong
			>
			per approved hour · {budget.scrapsPerHour} scraps/h · {budget.scrapsPerDollar} scraps/$
		</p>
	{/if}

	{#if error}
		<div class="rounded-2xl border-4 border-red-600 bg-red-50 p-4 font-bold text-red-700">
			couldn't load budget: {error}
		</div>
	{:else if loading && !budget}
		<p class="text-gray-500">loading…</p>
	{:else if budget}
		<div class="mb-8 grid gap-4 md:grid-cols-3">
			<div class="rounded-2xl border-4 p-5 {rateTone(budget.committed.perHour)}">
				<p class="text-sm font-bold text-gray-600">committed $/h</p>
				<p class="text-4xl font-bold">{money(budget.committed.perHour)}</p>
				<p class="mt-1 text-sm">{rateLabel(budget.committed.perHour)}</p>
				<p class="mt-2 text-xs text-gray-500">
					every scrap handed out (projects + bonuses) ÷ approved hours, if all of it gets spent
				</p>
			</div>
			<div class="rounded-2xl border-4 p-5 {rateTone(budget.projectedWithQueue.perHour)}">
				<p class="text-sm font-bold text-gray-600">projected $/h incl. review queue</p>
				<p class="text-4xl font-bold">{money(budget.projectedWithQueue.perHour)}</p>
				<p class="mt-1 text-sm">{rateLabel(budget.projectedWithQueue.perHour)}</p>
				<p class="mt-2 text-xs text-gray-500">
					as above, if the queue is approved at the current average multiplier (×{budget.queue
						.assumedMultiplier})
				</p>
			</div>
			<div class="rounded-2xl border-4 p-5 {rateTone(budget.delivered.perHour)}">
				<p class="text-sm font-bold text-gray-600">delivered $/h so far</p>
				<p class="text-4xl font-bold">{money(budget.delivered.perHour)}</p>
				<p class="mt-1 text-sm">{money(budget.delivered.dollars)} of items + shipping ordered</p>
				<p class="mt-2 text-xs text-gray-500">
					item value + fulfillment cost of every live order ÷ approved hours
				</p>
			</div>
		</div>

		<div class="mb-8 rounded-2xl border-4 border-black p-6">
			<h2 class="mb-1 text-2xl font-bold">before you approve the queue</h2>
			<p class="mb-4 text-sm text-gray-600">
				{budget.queue.projects} projects · {budget.queue.hours} effective hours waiting
			</p>
			{#if whatIf}
				<label for="whatIfScore" class="mb-1 flex items-baseline justify-between text-sm font-bold">
					<span>if the average reviewer score is</span>
					<span class="text-2xl"
						>{whatIfScore.toFixed(1)}
						<span class="text-base text-gray-500">(×{whatIf.mult.toFixed(2)})</span></span
					>
				</label>
				<input
					id="whatIfScore"
					type="range"
					min="1"
					max="3"
					step="0.1"
					bind:value={whatIfScore}
					class="w-full cursor-pointer"
				/>
				<div class="mt-4 grid gap-4 md:grid-cols-2">
					<div class="rounded-xl border-2 border-black p-4">
						<p class="text-sm text-gray-600">queue adds</p>
						<p class="text-2xl font-bold">{money(whatIf.queueDollars)}</p>
					</div>
					<div class="rounded-xl border-2 p-4 {rateTone(whatIf.perHour)}">
						<p class="text-sm text-gray-600">event-wide $/h after approving</p>
						<p class="text-2xl font-bold">{money(whatIf.perHour)}</p>
						<p class="text-sm">{rateLabel(whatIf.perHour)}</p>
					</div>
				</div>
				<p class="mt-3 text-xs text-gray-500">
					averages hide spread: half 1s + half 3s averages 2.0 but pays ×1.25, so keep 3s rare
				</p>
			{/if}
		</div>

		<div class="mb-8 grid gap-4 md:grid-cols-2">
			<div class="rounded-2xl border-4 border-black p-6">
				<h2 class="mb-4 text-xl font-bold">approved so far</h2>
				<dl class="grid grid-cols-2 gap-y-2 text-sm">
					<dt class="text-gray-600">projects</dt>
					<dd class="text-right font-bold">{num(budget.approved.projects)}</dd>
					<dt class="text-gray-600">approved hours</dt>
					<dd class="text-right font-bold">{budget.approved.hours}</dd>
					<dt class="text-gray-600">scraps awarded</dt>
					<dd class="text-right font-bold">{num(budget.approved.scrapsAwarded)}</dd>
					<dt class="text-gray-600">avg reviewer multiplier</dt>
					<dd class="text-right font-bold">
						{budget.approved.avgMultiplier == null ? '—' : `×${budget.approved.avgMultiplier}`}
					</dd>
					<dt class="text-gray-600">bonus-roll results (net)</dt>
					<dd class="text-right font-bold">{num(budget.approved.payoutRollScraps)}</dd>
					<dt class="text-gray-600">other bonuses (net)</dt>
					<dd class="text-right font-bold">{num(budget.bonusesScraps)}</dd>
				</dl>
				<p class="mt-4 mb-2 text-sm font-bold">payout bonus roll</p>
				<dl class="grid grid-cols-2 gap-y-2 text-sm">
					<dt class="text-gray-600">expected (optimal play)</dt>
					<dd class="text-right font-bold">×{budget.payoutRoll.expectedMultiplier.toFixed(2)}</dd>
					<dt class="text-gray-600">actual so far</dt>
					<dd
						class="text-right font-bold {budget.payoutRoll.realizedMultiplier != null &&
						budget.payoutRoll.realizedMultiplier > 1.05
							? 'text-red-600'
							: ''}"
					>
						{budget.payoutRoll.realizedMultiplier == null
							? '—'
							: `×${budget.payoutRoll.realizedMultiplier.toFixed(3)}`}
					</dd>
					<dt class="text-gray-600">payouts decided / rolled</dt>
					<dd class="text-right font-bold">
						{num(budget.payoutRoll.decided)} / {num(budget.payoutRoll.rolled)}
					</dd>
					<dt class="text-gray-600">still undecided</dt>
					<dd class="text-right font-bold">{num(budget.payoutRoll.undecided)}</dd>
				</dl>
				{#if budget.approved.scoreDistribution.length}
					<p class="mt-4 mb-2 text-sm font-bold">reviewer scores</p>
					<div class="flex flex-wrap gap-2">
						{#each budget.approved.scoreDistribution as s (s.score)}
							<span class="rounded-full border-2 border-black px-3 py-1 text-sm">
								{s.score.toFixed(1)}: <strong>{s.count}</strong>
							</span>
						{/each}
					</div>
				{/if}
			</div>

			<div class="rounded-2xl border-4 border-black p-6">
				<h2 class="mb-4 text-xl font-bold">scraps</h2>
				<dl class="grid grid-cols-2 gap-y-2 text-sm">
					<dt class="text-gray-600">handed out</dt>
					<dd class="text-right font-bold">
						{num(budget.committed.scraps)} ({money(budget.committed.dollars)})
					</dd>
					<dt class="text-gray-600">spent</dt>
					<dd class="text-right font-bold">{num(budget.spent.scraps)}</dd>
					<dt class="text-gray-600">…of which refinery</dt>
					<dd class="text-right font-bold">{num(budget.spent.refineryScraps)}</dd>
					<dt class="text-gray-600">refinery still undoable</dt>
					<dd class="text-right font-bold">{num(budget.spent.refineryUndoableScraps)}</dd>
					<dt class="text-gray-600">unspent (liability)</dt>
					<dd class="text-right font-bold">{num(budget.spent.unspentScraps)}</dd>
					<dt class="text-gray-600">unclaimed consolation rolls</dt>
					<dd class="text-right font-bold">{num(budget.unclaimedConsolation)}</dd>
				</dl>
			</div>
		</div>

		<div class="mb-8 rounded-2xl border-4 border-black p-6">
			<h2 class="mb-4 text-xl font-bold">spending by route</h2>
			{#if budget.routes.length === 0}
				<p class="text-sm text-gray-500">no orders yet</p>
			{:else}
				<div class="overflow-x-auto">
					<table class="w-full text-sm">
						<thead>
							<tr class="border-b-2 border-black text-left">
								<th class="py-2">route</th>
								<th class="py-2 text-right">orders</th>
								<th class="py-2 text-right">scraps paid</th>
								<th class="py-2 text-right">item value</th>
								<th class="py-2 text-right">paid ÷ value</th>
								<th class="py-2 text-right">shipping $</th>
							</tr>
						</thead>
						<tbody>
							{#each budget.routes as r (r.route)}
								{@const ratio = r.itemValueScraps > 0 ? r.scrapsPaid / r.itemValueScraps : null}
								<tr class="border-b border-gray-200">
									<td class="py-2 font-bold">{ROUTE_LABELS[r.route] ?? r.route}</td>
									<td class="py-2 text-right">{num(r.orders)}</td>
									<td class="py-2 text-right">{num(r.scrapsPaid)}</td>
									<td class="py-2 text-right"
										>{num(r.itemValueScraps)} ({money(
											r.itemValueScraps / budget.scrapsPerDollar
										)})</td
									>
									<td
										class="py-2 text-right font-bold {ratio != null && ratio < 1
											? 'text-red-600'
											: ''}">{ratio == null ? '—' : `${ratio.toFixed(2)}×`}</td
									>
									<td class="py-2 text-right">{money(r.fulfillmentDollars)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
				<p class="mt-2 text-xs text-gray-500">
					paid ÷ value under 1× means users got more value than they paid in scraps
				</p>
			{/if}
		</div>

		<div class="mb-8 rounded-2xl border-4 border-black p-6">
			<h2 class="mb-4 text-xl font-bold">gachapon payout</h2>
			<div class="overflow-x-auto">
				<table class="w-full text-sm">
					<thead>
						<tr class="border-b-2 border-black text-left">
							<th class="py-2">gachapon</th>
							<th class="py-2 text-right">price</th>
							<th class="py-2 text-right">expected prize</th>
							<th class="py-2 text-right">payout</th>
						</tr>
					</thead>
					<tbody>
						{#each budget.gachapons as g (g.id)}
							<tr class="border-b border-gray-200">
								<td class="py-2 font-bold">{g.name}</td>
								<td class="py-2 text-right">{num(g.price)}</td>
								<td class="py-2 text-right">{g.expectedPrizeScraps}</td>
								<td
									class="py-2 text-right font-bold {g.payoutRatio != null && g.payoutRatio > 1
										? 'text-red-600'
										: ''}"
								>
									{g.payoutRatio == null ? '—' : `${g.payoutRatio.toFixed(2)}×`}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
			<p class="mt-2 text-xs text-gray-500">
				payout over 1× means a pull is worth more than it costs (over budget)
			</p>
		</div>

		<p class="text-xs text-gray-500">
			dollar values use the current {budget.scrapsPerDollar} scraps/$. items priced before the 09-24 rate
			change (16 scraps/$) are counted at the new rate, so dollar figures here are an upper bound until
			each item stores its real dollar cost.
		</p>
	{/if}
</div>
