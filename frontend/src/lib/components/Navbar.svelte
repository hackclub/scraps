<script lang="ts">
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	import {
		Home,
		Package,
		Info,
		LayoutDashboard,
		Trophy,
		Store,
		Flame,
		Spool,
		LogOut,
		Shield,
		ClipboardList,
		Users,
		ShoppingBag,
		Newspaper,
		PackageCheck,
		Compass,
		BarChart3,
		Menu,
		X,
		Globe,
		Languages,
		ChevronDown
	} from '@lucide/svelte';
	import {
		logout,
		getUser,
		userScrapsStore,
		userScrapsPendingStore,
		nextPayoutDateStore
	} from '$lib/auth-client';
	import { t, locale, setLocale, type Locale } from '$lib/i18n';

	interface User {
		id: number;
		username: string;
		email: string;
		avatar: string | null;
		slackId: string | null;
		scraps: number;
		role?: string;
	}

	let user = $state<User | null>(null);
	let loading = $state(true);
	let showProfileMenu = $state(false);
	let showMobileMenu = $state(false);
	let showMoreMenu = $state(false);
	let activeSection = $state('home');
	let isScrolling = $state(false);
	let countdownText = $state('');

	let currentPath = $derived(page.url.pathname);
	let isHomePage = $derived(currentPath === '/');
	let isLoggedIn = $derived(user !== null);
	let isReviewer = $derived(user?.role === 'admin' || user?.role === 'reviewer' || user?.role === 'creator');
	let isAdminOnly = $derived(user?.role === 'admin' || user?.role === 'creator');
	let isInAdminSection = $derived(currentPath.startsWith('/admin'));
	let dashboardMoreActive = $derived(
		currentPath === '/leaderboard' || currentPath === '/shop' || currentPath === '/refinery'
	);
	let adminMoreActive = $derived(
		currentPath.startsWith('/admin/second-pass') ||
			currentPath.startsWith('/admin/shop') ||
			currentPath.startsWith('/admin/news') ||
			currentPath.startsWith('/admin/orders')
	);

	let observer: IntersectionObserver | null = null;

	onMount(() => {
		getUser().then((u) => {
			user = u;
			loading = false;
		});

		if (page.url.pathname === '/') {
			const sections = ['home', 'scraps', 'about'];
			observer = new IntersectionObserver(
				(entries) => {
					if (isScrolling) return;
					entries.forEach((entry) => {
						if (entry.isIntersecting && entry.intersectionRatio > 0.3) {
							activeSection = entry.target.id;
						}
					});
				},
				{
					threshold: [0.3, 0.5, 0.7],
					rootMargin: '-20% 0px -20% 0px'
				}
			);

			sections.forEach((id) => {
				const element = document.getElementById(id);
				if (element && observer) observer.observe(element);
			});
		}

		return () => {
			if (observer) observer.disconnect();
			if (countdownInterval) clearInterval(countdownInterval);
		};
	});

	function updateCountdown() {
		const payoutDate = $nextPayoutDateStore;
		if (!payoutDate) {
			countdownText = '';
			return;
		}
		const target = new Date(payoutDate).getTime();
		const now = Date.now();
		const diff = target - now;
		if (diff <= 0) {
			countdownText = 'payout soon!';
			return;
		}
		const hours = Math.floor(diff / (1000 * 60 * 60));
		const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
		if (hours >= 24) {
			const days = Math.floor(hours / 24);
			const remainingHours = hours % 24;
			countdownText = `${days}d ${remainingHours}h`;
		} else {
			countdownText = `${hours}h ${minutes}m`;
		}
	}

	let countdownInterval: ReturnType<typeof setInterval> | null = null;

	$effect(() => {
		// Re-run whenever nextPayoutDateStore changes
		$nextPayoutDateStore;
		updateCountdown();
		if (countdownInterval) clearInterval(countdownInterval);
		countdownInterval = setInterval(updateCountdown, 60_000);
	});

	function scrollToSection(sectionId: string) {
		isScrolling = true;
		activeSection = sectionId;
		showMobileMenu = false;
		if (sectionId === 'home') {
			window.scrollTo({ top: 0, behavior: 'smooth' });
		} else {
			const element = document.getElementById(sectionId);
			if (element) element.scrollIntoView({ behavior: 'smooth' });
		}
		setTimeout(() => {
			isScrolling = false;
		}, 1000);
	}

	function handleLogout() {
		showMobileMenu = false;
		logout();
	}

	function toggleProfileMenu() {
		showProfileMenu = !showProfileMenu;
	}

	function closeProfileMenu() {
		showProfileMenu = false;
	}

	function toggleMoreMenu() {
		showMoreMenu = !showMoreMenu;
	}

	function closeMoreMenu() {
		showMoreMenu = false;
	}

	function toggleMobileMenu() {
		showMobileMenu = !showMobileMenu;
	}

	function closeMobileMenu() {
		showMobileMenu = false;
	}

	function handleMobileNavClick() {
		showMobileMenu = false;
	}

	function toggleLanguage() {
		const newLocale: Locale = $locale === 'en' ? 'es' : 'en';
		setLocale(newLocale);
	}
</script>

<svelte:window
	onclick={(e) => {
		const target = e.target as HTMLElement;
		if (!target.closest('.profile-menu-container')) {
			closeProfileMenu();
		}
		if (!target.closest('.more-menu-container')) {
			closeMoreMenu();
		}
	}}
/>

<!-- Desktop navbar -->
<nav
	class="fixed top-0 right-0 left-0 z-50 hidden items-center justify-between bg-white/90 px-6 py-4 backdrop-blur-sm md:flex md:px-8 lg:px-12 xl:px-24 2xl:px-64"
>
	<a href={isLoggedIn ? '/dashboard' : '/'} class="shrink-0">
		<img src="/flag-standalone-bw.png" alt="Hack Club" class="h-8 md:h-10" />
	</a>

	{#if isHomePage}
		<!-- Landing page nav - home/scraps/about buttons -->
		<div class="flex items-center gap-2">
			<button
				onclick={() => scrollToSection('home')}
				class="flex cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 {activeSection ===
				'home'
					? 'border-black bg-black text-white'
					: 'border-black hover:border-dashed'}"
			>
				<Home size={18} />
				<span class="text-lg font-bold">{$t.nav.home}</span>
			</button>
			<button
				onclick={() => scrollToSection('scraps')}
				class="flex cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 {activeSection ===
				'scraps'
					? 'border-black bg-black text-white'
					: 'border-black hover:border-dashed'}"
			>
				<Package size={18} />
				<span class="text-lg font-bold">{$t.nav.scraps}</span>
			</button>
			<button
				onclick={() => scrollToSection('about')}
				class="flex cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 {activeSection ===
				'about'
					? 'border-black bg-black text-white'
					: 'border-black hover:border-dashed'}"
			>
				<Info size={18} />
				<span class="text-lg font-bold">{$t.nav.about}</span>
			</button>
			<button
				onclick={toggleLanguage}
				class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-6 py-2 transition-all duration-300 hover:border-dashed"
				title={$locale === 'en' ? 'Cambiar a Español' : 'Switch to English'}
			>
				<Languages size={18} />
				<span class="text-lg font-bold">{$locale === 'en' ? 'ES' : 'EN'}</span>
			</button>
		</div>
	{:else if isInAdminSection}
		<!-- Admin nav -->
		<div class="flex items-center gap-2">
			{#if loading}
				<!-- Skeleton loaders for admin nav -->
				<div class="rounded-full border-4 border-black px-6 py-2">
					<div class="h-6 w-20 animate-pulse rounded bg-gray-200"></div>
				</div>
				<div class="rounded-full border-4 border-black px-6 py-2">
					<div class="h-6 w-16 animate-pulse rounded bg-gray-200"></div>
				</div>
			{:else}
				<a
					href="/admin"
					class="flex cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 {currentPath ===
					'/admin'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<BarChart3 size={18} />
					<span class="text-lg font-bold">{$t.nav.info}</span>
				</a>

				<a
					href="/admin/reviews"
					class="flex cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 {currentPath.startsWith(
						'/admin/reviews'
					)
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<ClipboardList size={18} />
					<span class="text-lg font-bold">{$t.nav.reviews}</span>
				</a>

				<a
					href="/admin/users"
					class="flex cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 {currentPath.startsWith(
						'/admin/users'
					)
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<Users size={18} />
					<span class="text-lg font-bold">{$t.nav.users}</span>
				</a>

				{#if isAdminOnly}
					{#if user?.role === 'creator'}
						<!-- Visible on xl+ only -->
						<a
							href="/admin/second-pass"
							class="hidden cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 xl:flex {currentPath.startsWith(
								'/admin/second-pass'
							)
								? 'border-yellow-500 bg-yellow-500 text-white'
								: 'border-yellow-500 hover:border-dashed'}"
						>
							<ClipboardList size={18} />
							<span class="text-lg font-bold">2nd pass</span>
						</a>
					{/if}

					<a
						href="/admin/shop"
						class="hidden cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 xl:flex {currentPath.startsWith(
							'/admin/shop'
						)
							? 'border-black bg-black text-white'
							: 'border-black hover:border-dashed'}"
					>
						<ShoppingBag size={18} />
						<span class="text-lg font-bold">{$t.nav.shop}</span>
					</a>
					<a
						href="/admin/news"
						class="hidden cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 xl:flex {currentPath.startsWith(
							'/admin/news'
						)
							? 'border-black bg-black text-white'
							: 'border-black hover:border-dashed'}"
					>
						<Newspaper size={18} />
						<span class="text-lg font-bold">{$t.nav.news}</span>
					</a>
					<a
						href="/admin/orders"
						class="hidden cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 xl:flex {currentPath.startsWith(
							'/admin/orders'
						)
							? 'border-black bg-black text-white'
							: 'border-black hover:border-dashed'}"
					>
						<PackageCheck size={18} />
						<span class="text-lg font-bold">{$t.nav.orders}</span>
					</a>

					<!-- More dropdown for smaller screens -->
					<div class="more-menu-container relative xl:hidden">
						<button
							onclick={toggleMoreMenu}
							class="flex cursor-pointer items-center gap-1 rounded-full border-4 px-4 py-2 transition-all duration-300 {adminMoreActive
								? 'border-black bg-black text-white'
								: 'border-black hover:border-dashed'}"
						>
							<span class="text-lg font-bold">{$t.nav.more}</span>
							<ChevronDown
								size={16}
								class="transition-transform duration-200 {showMoreMenu ? 'rotate-180' : ''}"
							/>
						</button>
						{#if showMoreMenu}
							<div
								class="absolute top-full left-0 z-50 mt-2 min-w-48 overflow-hidden rounded-2xl border-4 border-black bg-white"
							>
								{#if user?.role === 'creator'}
									<a
										href="/admin/second-pass"
										onclick={closeMoreMenu}
										class="flex w-full cursor-pointer items-center gap-2 border-b-2 border-black px-4 py-3 transition-colors hover:bg-gray-100 {currentPath.startsWith(
											'/admin/second-pass'
										)
											? 'bg-yellow-50'
											: ''}"
									>
										<ClipboardList size={18} />
										<span class="font-bold">2nd pass</span>
									</a>
								{/if}
								<a
									href="/admin/shop"
									onclick={closeMoreMenu}
									class="flex w-full cursor-pointer items-center gap-2 border-b-2 border-black px-4 py-3 transition-colors hover:bg-gray-100 {currentPath.startsWith(
										'/admin/shop'
									)
										? 'bg-gray-100'
										: ''}"
								>
									<ShoppingBag size={18} />
									<span class="font-bold">{$t.nav.shop}</span>
								</a>
								<a
									href="/admin/news"
									onclick={closeMoreMenu}
									class="flex w-full cursor-pointer items-center gap-2 border-b-2 border-black px-4 py-3 transition-colors hover:bg-gray-100 {currentPath.startsWith(
										'/admin/news'
									)
										? 'bg-gray-100'
										: ''}"
								>
									<Newspaper size={18} />
									<span class="font-bold">{$t.nav.news}</span>
								</a>
								<a
									href="/admin/orders"
									onclick={closeMoreMenu}
									class="flex w-full cursor-pointer items-center gap-2 px-4 py-3 transition-colors hover:bg-gray-100 {currentPath.startsWith(
										'/admin/orders'
									)
										? 'bg-gray-100'
										: ''}"
								>
									<PackageCheck size={18} />
									<span class="font-bold">{$t.nav.orders}</span>
								</a>
							</div>
						{/if}
					</div>
				{/if}
			{/if}
		</div>
	{:else}
		<!-- Dashboard nav for logged-in users - centered -->
		<div class="flex items-center gap-2">
			<a
				href="/dashboard"
				class="flex cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 {currentPath ===
				'/dashboard'
					? 'border-black bg-black text-white'
					: 'border-black hover:border-dashed'}"
			>
				<LayoutDashboard size={18} />
				<span class="text-lg font-bold">{$t.nav.dashboard}</span>
			</a>

			<a
				href="/explore"
				class="flex cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 {currentPath ===
				'/explore'
					? 'border-black bg-black text-white'
					: 'border-black hover:border-dashed'}"
			>
				<Compass size={18} />
				<span class="text-lg font-bold">{$t.nav.explore}</span>
			</a>

			<!-- Visible on xl+ only -->
			<a
				href="/leaderboard"
				class="hidden cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 xl:flex {currentPath ===
				'/leaderboard'
					? 'border-black bg-black text-white'
					: 'border-black hover:border-dashed'}"
			>
				<Trophy size={18} />
				<span class="text-lg font-bold">{$t.nav.leaderboard}</span>
			</a>

			<a
				href="/shop"
				class="hidden cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 xl:flex {currentPath ===
				'/shop'
					? 'border-black bg-black text-white'
					: 'border-black hover:border-dashed'}"
			>
				<Store size={18} />
				<span class="text-lg font-bold">{$t.nav.shop}</span>
			</a>

			<a
				href="/refinery"
				class="hidden cursor-pointer items-center gap-2 rounded-full border-4 px-6 py-2 transition-all duration-300 xl:flex {currentPath ===
				'/refinery'
					? 'border-black bg-black text-white'
					: 'border-black hover:border-dashed'}"
			>
				<Flame size={18} />
				<span class="text-lg font-bold">{$t.nav.refinery}</span>
			</a>

			<!-- More dropdown for smaller screens -->
			<div class="more-menu-container relative xl:hidden">
				<button
					onclick={toggleMoreMenu}
					class="flex cursor-pointer items-center gap-1 rounded-full border-4 px-4 py-2 transition-all duration-300 {dashboardMoreActive
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<span class="text-lg font-bold">{$t.nav.more}</span>
					<ChevronDown
						size={16}
						class="transition-transform duration-200 {showMoreMenu ? 'rotate-180' : ''}"
					/>
				</button>
				{#if showMoreMenu}
					<div
						class="absolute top-full left-0 z-50 mt-2 min-w-48 overflow-hidden rounded-2xl border-4 border-black bg-white"
					>
						<a
							href="/leaderboard"
							onclick={closeMoreMenu}
							class="flex w-full cursor-pointer items-center gap-2 border-b-2 border-black px-4 py-3 transition-colors hover:bg-gray-100 {currentPath ===
							'/leaderboard'
								? 'bg-gray-100 font-bold'
								: ''}"
						>
							<Trophy size={18} />
							<span class="font-bold">{$t.nav.leaderboard}</span>
						</a>
						<a
							href="/shop"
							onclick={closeMoreMenu}
							class="flex w-full cursor-pointer items-center gap-2 border-b-2 border-black px-4 py-3 transition-colors hover:bg-gray-100 {currentPath ===
							'/shop'
								? 'bg-gray-100 font-bold'
								: ''}"
						>
							<Store size={18} />
							<span class="font-bold">{$t.nav.shop}</span>
						</a>
						<a
							href="/refinery"
							onclick={closeMoreMenu}
							class="flex w-full cursor-pointer items-center gap-2 px-4 py-3 transition-colors hover:bg-gray-100 {currentPath ===
							'/refinery'
								? 'bg-gray-100 font-bold'
								: ''}"
						>
							<Flame size={18} />
							<span class="font-bold">{$t.nav.refinery}</span>
						</a>
					</div>
				{/if}
			</div>
		</div>
	{/if}

	<!-- Right side: profile and scraps count (hidden on home page) -->
	{#if !isHomePage}
		<div class="flex shrink-0 items-center gap-4">
			{#if loading}
				<!-- Skeleton for scraps -->
				<div class="flex items-center gap-2 rounded-full border-4 border-black px-6 py-2">
					<Spool size={20} class="text-gray-300" />
					<div class="h-6 w-8 animate-pulse rounded bg-gray-200"></div>
				</div>
				<!-- Skeleton for profile -->
				<div class="h-10 w-10 animate-pulse rounded-full border-4 border-black bg-gray-200"></div>
			{:else if user}
				<div
					data-tutorial="scraps-counter"
					class="relative"
					title={$userScrapsPendingStore > 0
						? `+${$userScrapsPendingStore} pending — payout in ${countdownText}`
						: countdownText
							? `next payout in ${countdownText}`
							: ''}
				>
					<div class="flex items-center gap-2 rounded-full border-4 border-black px-6 py-2">
						<Spool size={20} />
						<span class="text-lg font-bold">{$userScrapsStore}</span>
						{#if $userScrapsPendingStore > 0}
							<span class="text-sm text-gray-500">+{$userScrapsPendingStore}</span>
						{/if}
					</div>
					{#if countdownText}
						<span
							class="absolute top-full left-1/2 mt-0.5 -translate-x-1/2 text-xs whitespace-nowrap text-gray-500"
							>⏱ {countdownText}</span
						>
					{/if}
				</div>

				<div class="profile-menu-container relative">
					<button
						onclick={toggleProfileMenu}
						class="h-10 w-10 cursor-pointer overflow-hidden rounded-full border-4 border-black transition-all duration-200 hover:border-dashed"
					>
						{#if user.avatar}
							<img
								src={user.avatar}
								alt={user.username || 'Profile'}
								class="h-full w-full object-cover"
							/>
						{:else}
							<div
								class="flex h-full w-full items-center justify-center bg-black text-lg font-bold text-white"
							>
								{(user.username || user.email || '?').charAt(0).toUpperCase()}
							</div>
						{/if}
					</button>

					{#if showProfileMenu}
						<div
							class="absolute top-14 right-0 z-50 min-w-48 overflow-hidden rounded-2xl border-4 border-black bg-white"
						>
							<div class="border-b-2 border-black px-4 py-3">
								<p class="truncate font-bold">{user.username || 'user'}</p>
								<p class="truncate text-sm text-gray-500">{user.email}</p>
							</div>
							<button
								onclick={toggleLanguage}
								class="flex w-full cursor-pointer items-center gap-2 border-b-2 border-black px-4 py-3 text-left transition-colors hover:bg-gray-100"
							>
								<Globe size={18} />
								<span class="font-bold">{$locale === 'en' ? 'Español' : 'English'}</span>
							</button>
							<button
								onclick={handleLogout}
								class="flex w-full cursor-pointer items-center gap-2 px-4 py-3 text-left transition-colors hover:bg-gray-100"
							>
								<LogOut size={18} />
								<span class="font-bold">{$t.nav.logout}</span>
							</button>
						</div>
					{/if}
				</div>
			{/if}
		</div>
	{:else}
		<!-- Empty placeholder to maintain justify-between spacing -->
		<div class="hidden w-0"></div>
	{/if}
</nav>

<!-- Mobile navbar -->
<nav
	class="fixed top-0 right-0 left-0 z-50 flex items-center justify-between bg-white/90 px-4 py-3 backdrop-blur-sm md:hidden"
>
	<a href={isLoggedIn ? '/dashboard' : '/'} class="shrink-0">
		<img src="/flag-standalone-bw.png" alt="Hack Club" class="h-8" />
	</a>

	<button
		onclick={toggleMobileMenu}
		class="flex h-10 w-10 cursor-pointer items-center justify-center rounded-lg border-4 border-black transition-all duration-200 hover:border-dashed"
		aria-label="Toggle menu"
	>
		{#if showMobileMenu}
			<X size={20} />
		{:else}
			<Menu size={20} />
		{/if}
	</button>
</nav>

<!-- Mobile menu overlay -->
{#if showMobileMenu}
	<div
		class="fixed inset-0 z-40 bg-black/50 md:hidden"
		onclick={closeMobileMenu}
		onkeydown={(e) => e.key === 'Escape' && closeMobileMenu()}
		role="button"
		tabindex="-1"
		aria-label="Close menu"
	></div>
{/if}

<!-- Mobile slide-out menu -->
<div
	class="fixed top-0 right-0 bottom-0 z-50 flex w-72 transform flex-col border-l-4 border-black bg-white transition-transform duration-300 ease-in-out md:hidden {showMobileMenu
		? 'translate-x-0'
		: 'translate-x-full'}"
>
	<!-- Close button at top -->
	<div class="flex justify-end p-4">
		<button
			onclick={closeMobileMenu}
			class="flex h-10 w-10 cursor-pointer items-center justify-center rounded-lg border-4 border-black transition-all duration-200 hover:border-dashed"
			aria-label="Close menu"
		>
			<X size={20} />
		</button>
	</div>

	<!-- Navigation links -->
	<div class="flex-1 overflow-y-auto px-4 pb-4">
		{#if isHomePage}
			<!-- Landing page nav -->
			<div class="flex flex-col gap-2">
				<button
					onclick={() => scrollToSection('home')}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {activeSection ===
					'home'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<Home size={20} />
					<span class="text-lg font-bold">{$t.nav.home}</span>
				</button>
				<button
					onclick={() => scrollToSection('scraps')}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {activeSection ===
					'scraps'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<Package size={20} />
					<span class="text-lg font-bold">{$t.nav.scraps}</span>
				</button>
				<button
					onclick={() => scrollToSection('about')}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {activeSection ===
					'about'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<Info size={20} />
					<span class="text-lg font-bold">{$t.nav.about}</span>
				</button>
				<button
					onclick={toggleLanguage}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 border-black px-4 py-3 transition-all duration-300 hover:border-dashed"
				>
					<Languages size={20} />
					<span class="text-lg font-bold">{$locale === 'en' ? 'Español' : 'English'}</span>
				</button>
			</div>
		{:else if isInAdminSection}
			<!-- Admin nav -->
			<div class="flex flex-col gap-2">
				{#if loading}
					<div class="rounded-full border-4 border-black px-4 py-3">
						<div class="h-6 w-full animate-pulse rounded bg-gray-200"></div>
					</div>
				{:else}
					<a
						href="/admin"
						onclick={handleMobileNavClick}
						class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath ===
						'/admin'
							? 'border-black bg-black text-white'
							: 'border-black hover:border-dashed'}"
					>
						<BarChart3 size={20} />
						<span class="text-lg font-bold">{$t.nav.info}</span>
					</a>

					<a
						href="/admin/reviews"
						onclick={handleMobileNavClick}
						class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath.startsWith(
							'/admin/reviews'
						)
							? 'border-black bg-black text-white'
							: 'border-black hover:border-dashed'}"
					>
						<ClipboardList size={20} />
						<span class="text-lg font-bold">{$t.nav.reviews}</span>
					</a>

					{#if user?.role === 'creator'}
						<a
							href="/admin/second-pass"
							onclick={handleMobileNavClick}
							class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath.startsWith(
								'/admin/second-pass'
							)
								? 'border-yellow-500 bg-yellow-500 text-white'
								: 'border-yellow-500 hover:border-dashed'}"
						>
							<ClipboardList size={20} />
							<span class="text-lg font-bold">2nd pass</span>
						</a>
					{/if}

					<a
						href="/admin/users"
						onclick={handleMobileNavClick}
						class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath.startsWith(
							'/admin/users'
						)
							? 'border-black bg-black text-white'
							: 'border-black hover:border-dashed'}"
					>
						<Users size={20} />
						<span class="text-lg font-bold">{$t.nav.users}</span>
					</a>

					{#if isAdminOnly}
						<a
							href="/admin/shop"
							onclick={handleMobileNavClick}
							class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath.startsWith(
								'/admin/shop'
							)
								? 'border-black bg-black text-white'
								: 'border-black hover:border-dashed'}"
						>
							<ShoppingBag size={20} />
							<span class="text-lg font-bold">{$t.nav.shop}</span>
						</a>
						<a
							href="/admin/news"
							onclick={handleMobileNavClick}
							class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath.startsWith(
								'/admin/news'
							)
								? 'border-black bg-black text-white'
								: 'border-black hover:border-dashed'}"
						>
							<Newspaper size={20} />
							<span class="text-lg font-bold">{$t.nav.news}</span>
						</a>
						<a
							href="/admin/orders"
							onclick={handleMobileNavClick}
							class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath.startsWith(
								'/admin/orders'
							)
								? 'border-black bg-black text-white'
								: 'border-black hover:border-dashed'}"
						>
							<PackageCheck size={20} />
							<span class="text-lg font-bold">{$t.nav.orders}</span>
						</a>
					{/if}
				{/if}
			</div>
		{:else}
			<!-- Dashboard nav -->
			<div class="flex flex-col gap-2">
				<a
					href="/dashboard"
					onclick={handleMobileNavClick}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath ===
					'/dashboard'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<LayoutDashboard size={20} />
					<span class="text-lg font-bold">{$t.nav.dashboard}</span>
				</a>

				<a
					href="/explore"
					onclick={handleMobileNavClick}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath ===
					'/explore'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<Compass size={20} />
					<span class="text-lg font-bold">{$t.nav.explore}</span>
				</a>

				<a
					href="/leaderboard"
					onclick={handleMobileNavClick}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath ===
					'/leaderboard'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<Trophy size={20} />
					<span class="text-lg font-bold">{$t.nav.leaderboard}</span>
				</a>

				<a
					href="/shop"
					onclick={handleMobileNavClick}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath ===
					'/shop'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<Store size={20} />
					<span class="text-lg font-bold">{$t.nav.shop}</span>
				</a>

				<a
					href="/refinery"
					onclick={handleMobileNavClick}
					class="flex cursor-pointer items-center gap-3 rounded-full border-4 px-4 py-3 transition-all duration-300 {currentPath ===
					'/refinery'
						? 'border-black bg-black text-white'
						: 'border-black hover:border-dashed'}"
				>
					<Flame size={20} />
					<span class="text-lg font-bold">{$t.nav.refinery}</span>
				</a>
			</div>
		{/if}
	</div>

	<!-- User profile section at bottom -->
	{#if !isHomePage}
		<div class="border-t-4 border-black p-4">
			{#if loading}
				<div class="mb-3 flex items-center gap-3">
					<div class="h-12 w-12 animate-pulse rounded-full border-4 border-black bg-gray-200"></div>
					<div class="flex-1">
						<div class="mb-1 h-5 w-24 animate-pulse rounded bg-gray-200"></div>
						<div class="h-4 w-32 animate-pulse rounded bg-gray-200"></div>
					</div>
				</div>
				<div class="flex items-center justify-between">
					<div class="flex items-center gap-2 rounded-full border-4 border-black px-4 py-2">
						<Spool size={18} class="text-gray-300" />
						<div class="h-5 w-8 animate-pulse rounded bg-gray-200"></div>
					</div>
				</div>
			{:else if user}
				<div class="mb-3 flex items-center gap-3">
					<div class="h-12 w-12 shrink-0 overflow-hidden rounded-full border-4 border-black">
						{#if user.avatar}
							<img
								src={user.avatar}
								alt={user.username || 'Profile'}
								class="h-full w-full object-cover"
							/>
						{:else}
							<div
								class="flex h-full w-full items-center justify-center bg-black text-xl font-bold text-white"
							>
								{(user.username || user.email || '?').charAt(0).toUpperCase()}
							</div>
						{/if}
					</div>
					<div class="min-w-0 flex-1">
						<p class="truncate font-bold">{user.username || 'user'}</p>
						<p class="truncate text-sm text-gray-500">{user.email}</p>
					</div>
				</div>
				<div class="flex items-center justify-between gap-2">
					<div class="flex flex-col items-start gap-1">
						<div class="flex items-center gap-2 rounded-full border-4 border-black px-4 py-2">
							<Spool size={18} />
							<span class="font-bold">{$userScrapsStore}</span>
							{#if $userScrapsPendingStore > 0}
								<span class="text-sm text-gray-400">(+{$userScrapsPendingStore})</span>
							{/if}
						</div>
						{#if countdownText}
							<span class="pl-2 text-xs text-gray-400">⏱ payout in {countdownText}</span>
						{/if}
					</div>
					<button
						onclick={toggleLanguage}
						class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-4 py-2 transition-all duration-200 hover:border-dashed"
					>
						<Globe size={18} />
						<span class="font-bold">{$locale === 'en' ? 'ES' : 'EN'}</span>
					</button>
					<button
						onclick={handleLogout}
						class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-4 py-2 transition-all duration-200 hover:border-dashed"
					>
						<LogOut size={18} />
						<span class="font-bold">{$t.nav.logout}</span>
					</button>
				</div>
			{/if}
		</div>
	{/if}
</div>

{#if isReviewer}
	<a
		href={isInAdminSection ? '/dashboard' : '/admin'}
		class="fixed bottom-6 left-6 z-50 flex cursor-pointer items-center gap-2 rounded-full border-4 border-red-800 bg-red-600 px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-red-700 md:px-6 md:py-3"
	>
		<Shield size={20} />
		<span class="hidden sm:inline">{isInAdminSection ? $t.nav.escape : $t.nav.admin}</span>
	</a>
{/if}
