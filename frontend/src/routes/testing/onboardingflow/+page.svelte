<script lang="ts">
	import { onMount } from 'svelte';
	import { Sparkles, RotateCcw } from '@lucide/svelte';
	import { onboardingSandbox } from '$lib/stores';

	onMount(() => onboardingSandbox.set(Date.now()));
</script>

<svelte:head>
	<title>onboarding flow sandbox - scraps</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="mx-auto max-w-3xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-2 flex items-center gap-2">
		<Sparkles size={28} />
		<h1 class="text-4xl font-bold md:text-5xl">onboarding flow</h1>
	</div>
	<p class="mb-6 text-lg text-gray-600">
		Scrappy walks you through the site. It runs in the layout, so it navigates you to the real
		dashboard / shop / refinery as it goes. Click or press Enter / Space to advance.
	</p>

	<button
		onclick={() => onboardingSandbox.set(Date.now())}
		class="flex cursor-pointer items-center gap-2 rounded-full bg-black px-6 py-3 font-bold text-white transition-all hover:bg-gray-800"
	>
		<RotateCcw size={18} /> restart from the top
	</button>

	<div class="mt-10 space-y-2 text-sm text-gray-600">
		<p class="font-bold text-black">what this covers</p>
		<ul class="list-disc space-y-1 pl-5">
			<li>intro (who Scrappy is, what Scraps is)</li>
			<li>making + shipping a project on the real dashboard, required fields highlighted</li>
			<li>an animated example payout, incl. the bonus-roll choice (lock in vs. gamble)</li>
			<li>the real shop: daily 5, one-time pick-any-2, drag to keep</li>
			<li>the refinery</li>
			<li>gachapons, ending on a pull of the (not-yet-created) onboarding gachapon</li>
		</ul>
		<p class="pt-2 text-xs text-gray-400">
			Leaving this page ends the run. The ship-checklist, pick-2 grid and onboarding-gachapon panel
			are still mocks.
		</p>
	</div>
</div>
