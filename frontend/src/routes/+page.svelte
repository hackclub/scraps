<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { Origami } from '@lucide/svelte';
	import Superscript from '$lib/components/Superscript.svelte';
	import { login, getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { t } from '$lib/i18n';

	let email = $state('');
	let emailError = $state('');
	let isSubmitting = $state(false);
	let isLoggedIn = $state(false);

	function isValidEmail(email: string): boolean {
		return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
	}

	async function handleLogin() {
		if (isLoggedIn) {
			goto('/dashboard');
			return;
		}

		emailError = '';

		if (!email.trim()) {
			emailError = $t.landing.pleaseEnterEmail;
			return;
		}

		if (!isValidEmail(email)) {
			emailError = $t.landing.pleaseEnterValidEmail;
			return;
		}

		isSubmitting = true;
		try {
			await fetch(`${API_URL}/auth/collect-email`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ email })
			});
			login();
		} catch {
			login();
		}
	}

	interface ShopItem {
		id: number;
		name: string;
		description: string;
		image: string;
		price: number;
		category: string;
	}

	interface ScrapItem {
		id: string;
		image: string;
		title: string;
		price: number;
		description?: string;
	}

	let shopItems = $state<ShopItem[]>([]);
	let row1ScrollPos = $state(0);
	let row2ScrollPos = $state(0);
	let isManualScrolling = $state(false);
	let manualScrollTimeout: ReturnType<typeof setTimeout>;

	const SCROLL_SPEED = 0.5;
	const ITEM_WIDTH = 280;
	const GAP = 16;

	function shopToScrapItems(items: ShopItem[]): ScrapItem[] {
		return items.map((item) => ({
			id: String(item.id),
			image: item.image || '/hero.png',
			title: item.name,
			price: item.price,
			description: item.description
		}));
	}

	function duplicateItems(items: ScrapItem[], times: number): ScrapItem[] {
		const result: ScrapItem[] = [];
		for (let i = 0; i < times; i++) {
			items.forEach((item, idx) => {
				result.push({ ...item, id: `${item.id}-${i}-${idx}` });
			});
		}
		return result;
	}

	let scrapItems = $derived(shopToScrapItems(shopItems));
	let row1Items = $derived(duplicateItems(scrapItems, 8));
	let row2Items = $derived(duplicateItems([...scrapItems].reverse(), 8));
	let totalSetWidth = $derived(scrapItems.length * (ITEM_WIDTH + GAP));

	onMount(() => {
		(async () => {
			const user = await getUser();
			isLoggedIn = !!user;

			try {
				const response = await fetch(`${API_URL}/shop/items`);
				if (response.ok) {
					shopItems = await response.json();
				}
			} catch (e) {
				console.error('Failed to fetch shop items:', e);
			}
		})();

		let animationId: number;

		function animate() {
			if (!isManualScrolling && totalSetWidth > 0) {
				row1ScrollPos += SCROLL_SPEED;
				row2ScrollPos += SCROLL_SPEED;

				if (row1ScrollPos >= totalSetWidth) {
					row1ScrollPos = row1ScrollPos - totalSetWidth;
				}
				if (row2ScrollPos >= totalSetWidth) {
					row2ScrollPos = row2ScrollPos - totalSetWidth;
				}
			}
			animationId = requestAnimationFrame(animate);
		}

		animate();

		return () => {
			cancelAnimationFrame(animationId);
		};
	});

	function handleWheel(e: WheelEvent, row: 1 | 2) {
		if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
			e.preventDefault();
			isManualScrolling = true;

			if (row === 1) {
				row1ScrollPos += e.deltaX;
				if (row1ScrollPos < 0) row1ScrollPos += totalSetWidth;
				if (row1ScrollPos >= totalSetWidth) row1ScrollPos -= totalSetWidth;
			} else {
				row2ScrollPos -= e.deltaX;
				if (row2ScrollPos < 0) row2ScrollPos += totalSetWidth;
				if (row2ScrollPos >= totalSetWidth) row2ScrollPos -= totalSetWidth;
			}

			clearTimeout(manualScrollTimeout);
			manualScrollTimeout = setTimeout(() => {
				isManualScrolling = false;
			}, 1000);
		}
	}
</script>

<!-- Hero Section -->
<div id="home" class="flex h-dvh w-full flex-col overflow-hidden">
	<div class="flex h-full w-full items-center justify-center md:absolute md:inset-0 md:h-full">
		<img
			src="/hero.png"
			alt="Dino throwing paper"
			class="h-auto max-h-[45vh] max-w-full object-contain md:max-h-screen"
		/>
	</div>

	<div class="w-full px-6 py-4 md:absolute md:right-1/4 md:bottom-1/5 md:w-auto md:max-w-lg md:p-0">
		<h1 class="mb-4 text-6xl font-bold md:text-8xl">{$t.nav.scraps}</h1>
		<p class="mb-1 text-lg md:text-xl">
			<strong>{$t.landing.youShip}</strong>
			{$t.landing.anyProject}<Superscript number={1} tooltip={$t.landing.sillyTooltip} />
		</p>
		<p class="mb-6 text-lg md:text-xl">
			<strong>{$t.landing.weShip}</strong>
			{$t.landing.chanceToWin}<Superscript number={2} tooltip={$t.landing.rareStickersTooltip} />
		</p>

		<!-- Auth Section -->
		<div class="flex flex-col gap-2">
			{#if !isLoggedIn}
				<input
					type="email"
					bind:value={email}
					placeholder={$t.landing.yourEmail}
					class="w-full rounded-full border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
				/>
				{#if emailError}
					<p class="px-4 text-sm text-red-500">{emailError}</p>
				{/if}
			{/if}
			<button
				onclick={handleLogin}
				disabled={isSubmitting}
				class="flex cursor-pointer items-center justify-center gap-2 rounded-full bg-black px-8 py-3 font-bold text-white transition-all hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
			>
				<Origami size={18} />
				<span>{isLoggedIn ? $t.landing.goToDashboard : $t.landing.startScrapping}</span>
			</button>
		</div>
	</div>
</div>

<!-- Scraps Section -->
<div id="scraps" class="flex min-h-dvh flex-col overflow-hidden">
	<div class="px-6 pt-24 pb-8 md:px-12">
		<div class="mx-auto max-w-3xl">
			<h2 class="mb-2 text-4xl font-bold md:text-6xl">{$t.nav.scraps}</h2>
			<p class="text-lg text-gray-600 md:text-xl">{$t.landing.itemsUpForGrabs}</p>
		</div>
	</div>

	<div class="flex w-screen flex-1 flex-col justify-center overflow-hidden pb-12">
		<!-- Row 1 - scrolling right, tilted up -->
		<div
			class="relative mb-8"
			style="transform: rotate(-3deg); margin-left: -100px; margin-right: -100px;"
		>
			<div
				class="flex cursor-grab gap-4 active:cursor-grabbing"
				style="transform: translateX({-row1ScrollPos}px);"
				onwheel={(e) => handleWheel(e, 1)}
				role="list"
			>
				{#each row1Items as item (item.id)}
					<div
						class="w-65 shrink-0 rounded-lg border-4 border-dashed border-black bg-white p-4 transition-all duration-300 hover:border-solid"
						role="listitem"
					>
						<img src={item.image} alt={item.title} class="mb-3 h-32 w-full object-contain" />
						<h3 class="text-lg font-bold">{item.title}</h3>
						<p class="text-sm text-gray-600">{item.price} scraps</p>
						{#if item.description}
							<p class="mt-1 text-sm">{item.description}</p>
						{/if}
					</div>
				{/each}
			</div>
		</div>

		<!-- Row 2 - scrolling left, tilted down -->
		<div
			class="relative"
			style="transform: rotate(3deg); margin-left: -100px; margin-right: -100px;"
		>
			<div
				class="flex cursor-grab gap-4 active:cursor-grabbing"
				style="transform: translateX({row2ScrollPos - totalSetWidth}px);"
				onwheel={(e) => handleWheel(e, 2)}
				role="list"
			>
				{#each row2Items as item (item.id)}
					<div
						class="w-65 shrink-0 rounded-lg border-4 border-dashed border-black bg-white p-4 transition-all duration-300 hover:border-solid"
						role="listitem"
					>
						<img src={item.image} alt={item.title} class="mb-3 h-32 w-full object-contain" />
						<h3 class="text-lg font-bold">{item.title}</h3>
						<p class="text-sm text-gray-600">{item.price} scraps</p>
						{#if item.description}
							<p class="mt-1 text-sm">{item.description}</p>
						{/if}
					</div>
				{/each}
			</div>
		</div>
	</div>
</div>

<!-- About Section -->
<div id="about" class="mx-auto min-h-dvh max-w-3xl px-6 pt-24 pb-24 md:px-12">
	<h2 class="mb-8 text-4xl font-bold md:text-6xl">{$t.landing.aboutScraps}</h2>

	<div class="prose prose-lg">
		<p class="mb-4 text-xl font-bold">{$t.landing.tldr}</p>

		<p class="mb-2">
			<strong>{$t.landing.youShip}</strong>
			{$t.landing.anyProject}
			<Superscript number={3} tooltip={$t.landing.optionallySillyTooltip} />
		</p>

		<p class="mb-6">
			<strong>{$t.landing.weShip}</strong>
			{$t.landing.weShipRandomItems}<Superscript number={4} tooltip={$t.landing.stickersTooltip} />
			{$t.landing.moreHoursMoreStuff}
		</p>

		<p class="mb-6">
			{$t.landing.coldAndWintery}<Superscript number={5} tooltip={$t.landing.vermontTooltip} />
			{$t.landing.atHackClubHQ}<Superscript number={6} tooltip={$t.landing.hardwareTooltip} />{$t
				.landing.postcardsAndMore}<Superscript
				number={7}
				tooltip={$t.landing.limitedEditionTooltip}
			/>!
		</p>

		<p class="mb-4 text-xl font-bold">{$t.landing.butHow}</p>

		<p class="mb-6">
			{$t.landing.simpleExplanation}<Superscript
				number={8}
				tooltip={$t.landing.anyProjectTooltip}
			/>{$t.landing.earnScraps}
			<a
				href="https://hackatime.hackclub.com"
				target="_blank"
				rel="noopener noreferrer"
				class="cursor-pointer underline hover:no-underline">{$t.landing.hackatime}</a
			>
			{$t.landing.watchScrapsRollIn}
		</p>

		<p class="mb-4 text-xl font-bold">{$t.landing.whatCanYouWin}</p>

		<p class="mb-6">
			{$t.landing.currentlyRandomAssortment}<Superscript
				number={9}
				tooltip={$t.landing.fudgeTooltip}
			/>{$t.landing.moreItemsPlanned}
			<strong>{$t.landing.stickers}</strong>
		</p>

		<p class="mb-6">
			{$t.landing.wonderedHowToGet}
			<a
				href="https://stickers.hackclub.com/"
				target="_blank"
				rel="noopener noreferrer"
				class="cursor-pointer underline hover:no-underline"
			>
				stickers.hackclub.com</a
			>{$t.landing.hereIsYourChance}<Superscript
				number={10}
				tooltip={$t.landing.collectionTooltip}
			/>{$t.landing.rarestStickers}
		</p>

		<p class="mb-6 text-xl font-bold">{$t.landing.faq}</p>

		<div class="grid gap-4 sm:grid-cols-2">
			<div
				class="rounded-2xl border-4 border-black bg-white p-6 transition-all hover:border-dashed"
			>
				<p class="mb-2 text-lg font-bold">{$t.about.whoIsEligible}</p>
				<p class="text-gray-600">
					{$t.about.whoIsEligibleAnswer}
				</p>
			</div>

			<div
				class="rounded-2xl border-4 border-black bg-white p-6 transition-all hover:border-dashed"
			>
				<p class="mb-2 text-lg font-bold">{$t.about.howMuchDoesItCost}</p>
				<p class="text-gray-600">
					{$t.about.howMuchDoesItCostAnswer}
				</p>
			</div>

			<div
				class="rounded-2xl border-4 border-black bg-white p-6 transition-all hover:border-dashed"
			>
				<p class="mb-2 text-lg font-bold">{$t.about.whatTypesOfProjects}</p>
				<p class="text-gray-600">
					{$t.about.whatTypesOfProjectsAnswer}
				</p>
			</div>

			<div
				class="rounded-2xl border-4 border-black bg-white p-6 transition-all hover:border-dashed"
			>
				<p class="mb-2 text-lg font-bold">{$t.about.howManyProjects}</p>
				<p class="text-gray-600">{$t.about.howManyProjectsAnswer}</p>
			</div>

			<div
				class="rounded-2xl border-4 border-black bg-white p-6 transition-all hover:border-dashed sm:col-span-2"
			>
				<p class="mb-2 text-lg font-bold">{$t.about.isThisLegit}</p>
				<p class="text-gray-600">
					{$t.about.isThisLegitAnswer}
					<a
						href="https://highseas.hackclub.com/"
						target="_blank"
						rel="noopener noreferrer"
						class="cursor-pointer underline hover:no-underline">{$t.about.highSeas}</a
					>
					{$t.about.and}
					<a
						href="https://summer.hackclub.com/"
						target="_blank"
						rel="noopener noreferrer"
						class="cursor-pointer underline hover:no-underline">{$t.about.summerOfMaking}</a
					>
					{$t.about.similarPrizes}
				</p>
			</div>
		</div>
	</div>
</div>

<style>
	:global(body) {
		overflow-x: hidden;
	}
</style>
