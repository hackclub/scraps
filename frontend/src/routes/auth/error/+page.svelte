<script lang="ts">
	import { page } from '$app/state';
	import { AlertTriangle } from '@lucide/svelte';
	import { t } from '$lib/i18n';

	let reason = $derived(page.url.searchParams.get('reason') || 'unknown');

	const errorConfigs: Record<
		string,
		{ key: 'needsVerification' | 'notEligible' | 'authFailed' | 'unknown'; redirectUrl?: string }
	> = {
		'needs-verification': {
			key: 'needsVerification',
			redirectUrl: 'https://auth.hackclub.com'
		},
		'not-eligible': {
			key: 'notEligible'
		},
		'auth-failed': {
			key: 'authFailed'
		},
		unknown: {
			key: 'unknown'
		}
	};

	let config = $derived(errorConfigs[reason] || errorConfigs['unknown']);

	let errorTitle = $derived(
		config.key === 'needsVerification'
			? $t.auth.needsVerification.title
			: config.key === 'notEligible'
				? $t.auth.notEligible.title
				: config.key === 'authFailed'
					? $t.auth.authFailed.title
					: $t.auth.unknown.title
	);

	let errorDescription = $derived(
		config.key === 'needsVerification'
			? $t.auth.needsVerification.description
			: config.key === 'notEligible'
				? $t.auth.notEligible.description
				: config.key === 'authFailed'
					? $t.auth.authFailed.description
					: $t.auth.unknown.description
	);

	let redirectText = $derived(
		config.key === 'needsVerification' ? $t.auth.needsVerification.redirectText : ''
	);
</script>

<svelte:head>
	<title>{$t.auth.error} - scraps</title>
</svelte:head>

<div class="flex min-h-dvh items-center justify-center px-6">
	<div class="max-w-md text-center">
		<div class="mb-6 flex justify-center">
			<div class="flex h-24 w-24 items-center justify-center rounded-full bg-red-100">
				<AlertTriangle size={48} class="text-red-600" />
			</div>
		</div>

		<h1 class="mb-4 text-4xl font-bold md:text-5xl">{errorTitle}</h1>
		<p class="mb-8 text-lg text-gray-600">{errorDescription}</p>

		<div class="flex flex-col items-center justify-center gap-4 sm:flex-row">
			<a
				href="/"
				class="cursor-pointer rounded-full border-4 border-black px-6 py-3 font-bold transition-all hover:border-dashed"
			>
				{$t.auth.goBackHome}
			</a>
			{#if config.redirectUrl}
				<a
					href={config.redirectUrl}
					target="_blank"
					rel="noopener noreferrer"
					class="cursor-pointer rounded-full bg-black px-6 py-3 font-bold text-white transition-all hover:bg-gray-800"
				>
					{redirectText}
				</a>
			{:else}
				<a
					href="https://hackclub.com/slack"
					target="_blank"
					rel="noopener noreferrer"
					class="cursor-pointer rounded-full bg-black px-6 py-3 font-bold text-white transition-all hover:bg-gray-800"
				>
					{$t.auth.getHelpOnSlack}
				</a>
			{/if}
		</div>
	</div>
</div>
