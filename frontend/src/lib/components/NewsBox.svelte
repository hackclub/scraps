<script lang="ts">
	import { onMount } from 'svelte';
	import { ChevronLeft, ChevronRight, ChevronDown } from '@lucide/svelte';
	import { newsStore, newsLoading, fetchNews } from '$lib/stores';
	import { t } from '$lib/i18n';

	let newsIndex = $state(0);
	let newsPaused = $state(false);
	let expandedId = $state<string | null>(null);
	let overflowing = $state<Record<string, boolean>>({});

	function measure(node: HTMLElement, key: string) {
		const check = () => {
			if (expandedId === key) return;
			const title = node.querySelector<HTMLElement>('[data-title]');
			const body = node.querySelector<HTMLElement>('[data-body]');
			const over =
				(!!title && title.scrollWidth > title.clientWidth + 1) ||
				(!!body && body.scrollHeight > body.clientHeight + 1);
			if (overflowing[key] !== over) overflowing[key] = over;
		};
		const ro = new ResizeObserver(check);
		ro.observe(node);
		check();
		return { destroy: () => ro.disconnect() };
	}

	function go(i: number) {
		expandedId = null;
		newsIndex = i;
	}

	onMount(() => {
		fetchNews();
		const id = setInterval(() => {
			if (!newsPaused && expandedId === null && $newsStore.length > 1)
				go((newsIndex + 1) % $newsStore.length);
		}, 5000);
		return () => clearInterval(id);
	});
</script>

{#if !$newsLoading}
	<div
		class="w-full shrink-0 rounded-2xl border-4 border-black px-4 py-3 md:w-80"
		onmouseenter={() => (newsPaused = true)}
		onmouseleave={() => (newsPaused = false)}
		role="region"
		aria-label="news"
	>
		<div class="mb-1 flex items-center justify-between">
			<p class="text-xs font-bold text-gray-500">{$t.news.title}</p>
			{#if $newsStore.length > 1}
				<div class="flex items-center gap-1">
					<button
						onclick={() => go((newsIndex - 1 + $newsStore.length) % $newsStore.length)}
						aria-label={$t.news.previousNews}
						class="cursor-pointer rounded p-0.5 hover:bg-gray-100"><ChevronLeft size={14} /></button
					>
					<button
						onclick={() => go((newsIndex + 1) % $newsStore.length)}
						aria-label={$t.news.nextNews}
						class="cursor-pointer rounded p-0.5 hover:bg-gray-100"
						><ChevronRight size={14} /></button
					>
				</div>
			{/if}
		</div>
		{#if $newsStore.length === 0}
			<p class="text-sm text-gray-500">{$t.news.noNewsRightNow}</p>
		{:else}
			<div class="overflow-hidden">
				<div
					class="flex items-start transition-transform duration-500 ease-in-out"
					style="transform: translateX(-{(newsIndex % $newsStore.length) * 100}%)"
				>
					{#each $newsStore as item (item.id)}
						{@const key = String(item.id)}
						{@const open = expandedId === key}
						<div class="w-full min-w-0 shrink-0" use:measure={key}>
							<p data-title class="font-bold {open ? 'break-words' : 'truncate'}">{item.title}</p>
							<p
								data-body
								class="text-sm text-gray-600 {open
									? 'max-h-60 overflow-y-auto break-words whitespace-pre-line'
									: 'line-clamp-2'}"
							>
								{item.content}
							</p>
							{#if overflowing[key] || open}
								<button
									onclick={() => (expandedId = open ? null : key)}
									aria-expanded={open}
									class="mt-1 flex cursor-pointer items-center gap-0.5 text-xs font-bold text-gray-700 hover:underline"
								>
									{open ? 'show less' : 'read more'}
									<ChevronDown size={12} class="transition-transform {open ? 'rotate-180' : ''}" />
								</button>
							{/if}
							<p class="mt-1 text-xs text-gray-400">
								{new Date(item.createdAt)
									.toLocaleDateString('en-US', {
										month: 'short',
										day: 'numeric',
										year: 'numeric'
									})
									.toLowerCase()}
							</p>
						</div>
					{/each}
				</div>
			</div>
		{/if}
	</div>
{/if}
