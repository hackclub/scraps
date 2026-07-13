<script lang="ts">
	import './layout.css';
	import { page } from '$app/stores';
	import { onMount } from 'svelte';
	import favicon from '$lib/assets/favicon.ico';
	import Navbar from '$lib/components/Navbar.svelte';
	import Footer from '$lib/components/Footer.svelte';
	import Tutorial from '$lib/components/Tutorial.svelte';
	import ErrorModal from '$lib/components/ErrorModal.svelte';
	import Toast from '$lib/components/Toast.svelte';
	import { handleNavigation, prefetchUserData } from '$lib/stores';
	import { getUser, type User } from '$lib/auth-client';

	let { children } = $props();

	let previousPath = $state('');
	let showTutorial = $state(false);
	let user = $state<User | null>(null);

	// Handle navigation changes
	$effect(() => {
		const currentPath = $page.url.pathname;
		if (currentPath !== previousPath) {
			handleNavigation(currentPath);
			previousPath = currentPath;
		}
	});

	let hideNavbar = $derived($page.url.pathname.startsWith('/auth/error'));

	// Prefetch data on initial load if user is logged in
	onMount(async () => {
		// Fetch server config early on client startup so the UI can read canonical values.
		// Use dynamic import here so we don't need to modify top-level imports in this file.
		import('$lib/config')
			.then((m) => m.fetchServerConfig())
			.catch(() => {
				/* ignore errors; UI can fallback to local values */
			});

		user = await getUser();
		if (user) {
			prefetchUserData();
			// Show tutorial for users who haven't completed it
			if (!user.tutorialCompleted) {
				showTutorial = true;
			}
		}
	});

	function handleTutorialComplete() {
		showTutorial = false;
	}
</script>

<svelte:head>
	<title>scraps - Hack Club</title>
	<link rel="icon" href={favicon} />
	<link rel="apple-touch-icon" href={favicon} />
	<meta name="viewport" content="width=device-width,initial-scale=1" />
	<meta name="apple-mobile-web-app-capable" content="yes" />
	<meta name="mobile-web-app-capable" content="yes" />
	<meta
		name="description"
		content="Build projects, earn scraps, test your luck, get prizes. A Hack Club program for teen coders."
	/>
	<meta name="author" content="Hack Club" />
	<meta name="keywords" content="hack club, scraps, ysws, projects, coding, prizes" />
	<meta name="theme-color" content="#000000" />
	<meta property="og:type" content="website" />
	<meta property="og:locale" content="en_US" />
	<meta property="og:site_name" content="scraps - Hack Club" />
	<meta property="og:title" content="scraps - Hack Club" />
	<meta
		property="og:description"
		content="Build projects, earn scraps, test your luck, get prizes. A Hack Club program for teen coders."
	/>
	<meta property="og:image" content={favicon} />
	<meta name="twitter:card" content="summary" />
	<meta name="twitter:site" content="@hackclub" />
	<meta name="twitter:creator" content="@hackclub" />
	<meta name="twitter:title" content="scraps - Hack Club" />
	<meta
		name="twitter:description"
		content="Build projects, earn scraps, test your luck, get prizes. A Hack Club program for teen coders."
	/>
	<meta name="twitter:image" content={favicon} />
</svelte:head>

<div class="flex min-h-dvh flex-col">
	{#if !hideNavbar}
		<Navbar />
	{/if}
	<main class="flex-1">
		{@render children()}
	</main>
	<Footer />
</div>

{#if showTutorial}
	<Tutorial onComplete={handleTutorialComplete} />
{/if}

<ErrorModal />
<Toast />
