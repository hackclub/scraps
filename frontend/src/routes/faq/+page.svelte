<script lang="ts">
	import { ChevronDown } from '@lucide/svelte';
	import { t } from '$lib/i18n';

	interface FAQItem {
		question: string;
		answer: string;
	}

	const faqs: FAQItem[] = $derived([
		{
			question: $t.faq.whatIsScraps,
			answer: $t.faq.whatIsScrapsAnswer
		},
		{
			question: $t.faq.howDoIEarnScraps,
			answer: $t.faq.howDoIEarnScrapsAnswer
		},
		{
			question: $t.faq.whatIsHackatime,
			answer: $t.faq.whatIsHackatimeAnswer
		},
		{
			question: $t.faq.howDoesShopWork,
			answer: $t.faq.howDoesShopWorkAnswer
		},
		{
			question: $t.faq.whatIsRefinery,
			answer: $t.faq.whatIsRefineryAnswer
		},
		{
			question: $t.faq.whatAreProjectTiers,
			answer: $t.faq.whatAreProjectTiersAnswer
		},
		{
			question: $t.faq.howLongDoesReviewTake,
			answer: $t.faq.howLongDoesReviewTakeAnswer
		},
		{
			question: $t.faq.whatIfILoseRoll,
			answer: $t.faq.whatIfILoseRollAnswer
		},
		{
			question: $t.faq.canISubmitAnyProject,
			answer: $t.faq.canISubmitAnyProjectAnswer
		},
		{
			question: $t.faq.howDoIGetStarted,
			answer: $t.faq.howDoIGetStartedAnswer
		}
	]);

	let openIndex = $state<number | null>(null);

	function toggle(index: number) {
		openIndex = openIndex === index ? null : index;
	}
</script>

<svelte:head>
	<title>{$t.faq.pageTitle}</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<div class="mb-12 text-center">
		<h1 class="mb-4 text-4xl font-bold md:text-5xl">{$t.faq.title}</h1>
		<p class="text-lg text-gray-600">{$t.faq.subtitle}</p>
	</div>

	<div class="space-y-4">
		{#each faqs as faq, i}
			<div class="rounded-2xl border-4 border-black transition-all hover:border-dashed">
				<button
					onclick={() => toggle(i)}
					class="flex w-full cursor-pointer items-center justify-between p-6 text-left"
				>
					<span class="text-lg font-bold">{faq.question}</span>
					<ChevronDown
						size={24}
						class="shrink-0 transition-transform duration-200 {openIndex === i ? 'rotate-180' : ''}"
					/>
				</button>
				{#if openIndex === i}
					<div class="border-t-4 border-black px-6 py-4">
						<p class="text-gray-600">{@html faq.answer}</p>
					</div>
				{/if}
			</div>
		{/each}
	</div>

	<div class="mt-12 rounded-2xl border-4 border-black bg-gray-50 p-8 text-center">
		<h2 class="mb-4 text-2xl font-bold">{$t.faq.stillHaveQuestions}</h2>
		<p class="mb-6 text-gray-600">
			{$t.faq.reachOutOnSlack}
		</p>
		<a
			href="https://slack.hackclub.com/"
			target="_blank"
			rel="noopener noreferrer"
			class="inline-block cursor-pointer rounded-full bg-black px-8 py-3 font-bold text-white transition-all duration-200 hover:bg-gray-800"
		>
			{$t.faq.joinSlack}
		</a>
	</div>
</div>
