<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { getUser } from '$lib/auth-client';
	import { t } from '$lib/i18n';

	let loading = $state(true);
	let error = $state<string | null>(null);

	onMount(async () => {
		try {
			const urlParams = new URLSearchParams(window.location.search);
			const authError = urlParams.get('error');

			if (authError === 'not-eligible') {
				goto('/auth/error?reason=not-eligible');
				return;
			}

			const user = await getUser();
			if (user) {
				goto('/dashboard');
			} else {
				error = $t.auth.authenticationFailed;
			}
		} catch (e) {
			console.error('Auth callback error:', e);
			error = $t.auth.errorDuringAuth;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head>
	<title>{$t.auth.authenticating} - scraps</title>
</svelte:head>

<div class="flex min-h-dvh items-center justify-center">
	{#if loading}
		<div class="text-center">
			<h1 class="mb-4 text-4xl font-bold">{$t.auth.authenticating}</h1>
			<p class="text-gray-600">{$t.auth.pleaseWait}</p>
		</div>
	{:else if error}
		<div class="text-center">
			<h1 class="mb-4 text-4xl font-bold text-red-600">{$t.auth.oops}</h1>
			<p class="mb-6 text-gray-600">{error}</p>
			<a
				href="/"
				class="cursor-pointer rounded-full border-4 border-black px-6 py-2 font-bold transition-all hover:border-dashed"
			>
				{$t.auth.goBackHome}
			</a>
		</div>
	{/if}
</div>
