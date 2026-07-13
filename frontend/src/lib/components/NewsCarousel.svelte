<script lang="ts">
	import { onMount } from 'svelte';
	import { ChevronLeft, ChevronRight } from '@lucide/svelte';
	import { newsStore, newsLoading, fetchNews } from '$lib/stores';
	import { t, locale } from '$lib/i18n';

	let currentIndex = $state(0);
	let isPaused = $state(false);

	const AUTO_SCROLL_INTERVAL = 5000;

	onMount(() => {
		fetchNews();

		const interval = setInterval(() => {
			if (!isPaused && $newsStore.length > 1) {
				currentIndex = (currentIndex + 1) % $newsStore.length;
			}
		}, AUTO_SCROLL_INTERVAL);

		return () => clearInterval(interval);
	});

	function goTo(index: number) {
		currentIndex = index;
	}

	function prev() {
		currentIndex = currentIndex === 0 ? $newsStore.length - 1 : currentIndex - 1;
	}

	function next() {
		currentIndex = (currentIndex + 1) % $newsStore.length;
	}

	function formatDate(dateString: string) {
		return new Date(dateString).toLocaleDateString($locale === 'es' ? 'es-ES' : 'en-US', {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}
</script>

{#if !$newsLoading}
	<div
		class="relative mb-8 overflow-hidden rounded-2xl border-4 border-black p-6"
		onmouseenter={() => (isPaused = true)}
		onmouseleave={() => (isPaused = false)}
		role="region"
		aria-label="News carousel"
	>
		<div class="mb-2 flex items-center justify-between">
			<h2 class="text-lg font-bold">{$t.news.title}</h2>
			{#if $newsStore.length > 1}
				<div class="flex items-center gap-2">
					<button
						onclick={prev}
						class="cursor-pointer rounded p-1 transition-colors hover:bg-gray-100"
						aria-label={$t.news.previousNews}
					>
						<ChevronLeft size={20} />
					</button>
					<button
						onclick={next}
						class="cursor-pointer rounded p-1 transition-colors hover:bg-gray-100"
						aria-label={$t.news.nextNews}
					>
						<ChevronRight size={20} />
					</button>
				</div>
			{/if}
		</div>

		{#if $newsStore.length === 0}
			<p class="text-gray-500">{$t.news.noNewsRightNow}</p>
		{:else}
			<div class="relative h-20 overflow-hidden">
				{#each $newsStore as item, index (item.id)}
					<div
						class="absolute inset-0 transition-all duration-500 ease-in-out {index === currentIndex
							? 'translate-x-0 opacity-100'
							: index < currentIndex
								? '-translate-x-full opacity-0'
								: 'translate-x-full opacity-0'}"
					>
						<p class="mb-1 text-xl font-bold">{item.title}</p>
						<p class="text-gray-600">{item.content}</p>
						<p class="mt-1 text-sm text-gray-400">{formatDate(item.createdAt)}</p>
					</div>
				{/each}
			</div>

			{#if $newsStore.length > 1}
				<div class="mt-4 flex justify-center gap-2">
					{#each $newsStore as _, index}
						<button
							onclick={() => goTo(index)}
							class="h-2 w-2 cursor-pointer rounded-full transition-all duration-300 {index ===
							currentIndex
								? 'w-6 bg-black'
								: 'bg-gray-300 hover:bg-gray-400'}"
							aria-label="{$t.news.goToNews} {index + 1}"
						></button>
					{/each}
				</div>
			{/if}
		{/if}
	</div>
{/if}
