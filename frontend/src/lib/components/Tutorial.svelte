<script lang="ts">
	import {
		Origami,
		ShoppingBag,
		Flame,
		Trophy,
		Clock,
		Gift,
		Sparkles,
		ArrowRight,
		X,
		LayoutDashboard,
		Plus,
		Layers
	} from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { refreshUserScraps } from '$lib/auth-client';
	import { goto, preloadData } from '$app/navigation';
	import { tutorialActiveStore } from '$lib/stores';
	import { onMount, onDestroy } from 'svelte';
	import { t } from '$lib/i18n';

	let { onComplete }: { onComplete: () => void } = $props();

	let currentStep = $state(0);
	let loading = $state(false);

	// Dragging state
	let isDragging = $state(false);
	let dragOffset = $state({ x: 0, y: 0 });
	let cardOffset = $state<{ x: number; y: number } | null>(null);

	function handleDragStart(e: MouseEvent) {
		isDragging = true;
		const card = (e.target as HTMLElement).closest('[data-tutorial-card]') as HTMLElement;
		if (card) {
			const rect = card.getBoundingClientRect();
			dragOffset = {
				x: e.clientX - rect.left,
				y: e.clientY - rect.top
			};
			if (!cardOffset) {
				cardOffset = { x: rect.left, y: rect.top };
			}
		}
	}

	function handleDragMove(e: MouseEvent) {
		if (!isDragging) return;
		cardOffset = {
			x: e.clientX - dragOffset.x,
			y: e.clientY - dragOffset.y
		};
	}

	function handleDragEnd() {
		isDragging = false;
	}

	// Reset card position when step changes
	$effect(() => {
		currentStep;
		cardOffset = null;
	});

	onMount(() => {
		tutorialActiveStore.set(true);
		window.addEventListener('mousemove', handleDragMove);
		window.addEventListener('mouseup', handleDragEnd);
		// Preload pages that the tutorial will navigate to
		preloadData('/dashboard');
		preloadData('/shop');
	});

	onDestroy(() => {
		tutorialActiveStore.set(false);
		window.removeEventListener('mousemove', handleDragMove);
		window.removeEventListener('mouseup', handleDragEnd);
	});

	const stepConfigs = [
		{ titleKey: 'welcomeTitle', descKey: 'welcomeDesc', highlight: null },
		{ titleKey: 'navigationTitle', descKey: 'navigationDesc', highlight: 'navbar' },
		{ titleKey: 'createProjectsTitle', descKey: 'createProjectsDesc', highlight: 'dashboard' },
		{
			titleKey: 'createFirstProjectTitle',
			descKey: 'createFirstProjectDesc',
			highlight: 'new-project-button',
			waitForClick: true
		},
		{
			titleKey: 'fillDetailsTitle',
			descKey: 'fillDetailsDesc',
			highlight: 'create-project-modal',
			waitForEvent: 'tutorial:project-created'
		},
		{
			titleKey: 'projectPageTitle',
			descKey: 'projectPageDesc',
			highlight: null,
			position: 'bottom-center'
		},
		{ titleKey: 'submitReviewTitle', descKey: 'submitReviewDesc', highlight: 'submit-button' },
		{ titleKey: 'projectTiersTitle', descKey: 'projectTiersDesc', highlight: null },
		{ titleKey: 'earnScrapsTitle', descKey: 'earnScrapsDesc', highlight: 'scraps-counter' },
		{ titleKey: 'shopTitle', descKey: 'shopDesc', highlight: 'shop' },
		{ titleKey: 'refineryTitle', descKey: 'refineryDesc', highlight: 'refinery' },
		{ titleKey: 'strategyTitle', descKey: 'strategyDesc', highlight: null },
		{ titleKey: 'readyTitle', descKey: 'readyDesc', highlight: null }
	];

	let steps = $derived(
		stepConfigs.map((config) => ({
			title:
				$t.tutorial.steps[config.titleKey as keyof typeof $t.tutorial.steps] || config.titleKey,
			description:
				$t.tutorial.steps[config.descKey as keyof typeof $t.tutorial.steps] || config.descKey,
			highlight: config.highlight,
			waitForClick: (config as { waitForClick?: boolean }).waitForClick,
			waitForEvent: (config as { waitForEvent?: string }).waitForEvent,
			position: (config as { position?: string }).position
		}))
	);

	let currentStepData = $derived(steps[currentStep]);
	let isLastStep = $derived(currentStep === steps.length - 1);
	let stepProgress = $derived(
		$t.tutorial.stepOf
			.replace('{current}', String(currentStep + 1))
			.replace('{total}', String(steps.length))
	);

	function getHighlightPosition(highlight: string | null): {
		top: number;
		left: number;
		width: number;
		height: number;
	} | null {
		if (!highlight) return null;

		const selectors: Record<string, string> = {
			navbar: 'nav',
			dashboard: 'a[href="/dashboard"]',
			shop: 'a[href="/shop"]',
			refinery: 'a[href="/refinery"]',
			leaderboard: 'a[href="/leaderboard"]',
			'new-project-button': 'button[data-tutorial="new-project"]',
			'create-project-modal': '[data-tutorial="create-project-modal"]',
			'submit-button': '[data-tutorial="submit-button"]',
			'scraps-counter': '[data-tutorial="scraps-counter"]'
		};

		const selector = selectors[highlight];
		if (!selector) return null;

		const element = document.querySelector(selector);
		if (!element) return null;

		const rect = element.getBoundingClientRect();
		return {
			top: rect.top,
			left: rect.left,
			width: rect.width,
			height: rect.height
		};
	}

	let highlightTick = $state(0);
	let highlightRect = $derived.by(() => {
		highlightTick; // trigger reactivity
		return getHighlightPosition(currentStepData.highlight);
	});

	// Re-calculate highlight position after a short delay when step changes
	$effect(() => {
		const highlight = currentStepData.highlight;
		if (highlight) {
			const timeout = setTimeout(() => {
				highlightTick++;
			}, 100);
			return () => clearTimeout(timeout);
		}
	});

	let cardPosition = $derived.by(() => {
		// Check for explicit position override first
		const explicitPosition = (currentStepData as { position?: string }).position;
		if (explicitPosition) {
			return explicitPosition;
		}
		const highlight = currentStepData.highlight;
		if (
			highlight === 'navbar' ||
			highlight === 'dashboard' ||
			highlight === 'shop' ||
			highlight === 'refinery' ||
			highlight === 'leaderboard' ||
			highlight === 'scraps-counter'
		) {
			return 'bottom';
		}
		if (highlight === 'create-project-modal' || highlight === 'submit-button') {
			return 'left';
		}
		if (highlight === 'new-project-button') {
			return 'right';
		}
		return 'center';
	});

	$effect(() => {
		if (currentStepData.highlight === 'shop') {
			goto('/shop', { invalidateAll: false });
		} else if (
			currentStepData.highlight === 'dashboard' ||
			currentStepData.highlight === 'new-project-button'
		) {
			goto('/dashboard', { invalidateAll: false });
		}
	});

	// Listen for clickable element clicks to advance tutorial
	$effect(() => {
		if (currentStepData.waitForClick && currentStepData.highlight) {
			const selectors: Record<string, string> = {
				'new-project-button': 'button[data-tutorial="new-project"]',
				'submit-button': '[data-tutorial="submit-button"]'
			};
			const selector = selectors[currentStepData.highlight];
			if (selector) {
				const element = document.querySelector(selector);
				if (element) {
					const handleClick = () => {
						nextStep();
					};
					element.addEventListener('click', handleClick);
					return () => element.removeEventListener('click', handleClick);
				}
			}
		}
	});

	// Listen for custom events to advance tutorial (e.g., project created)
	$effect(() => {
		const waitForEvent = (currentStepData as { waitForEvent?: string }).waitForEvent;
		if (waitForEvent) {
			const handleEvent = () => {
				nextStep();
			};
			window.addEventListener(waitForEvent, handleEvent);
			return () => window.removeEventListener(waitForEvent, handleEvent);
		}
	});

	function nextStep() {
		if (isLastStep) {
			completeTutorial();
		} else {
			currentStep++;
		}
	}

	function skip() {
		completeTutorial();
	}

	async function completeTutorial() {
		loading = true;
		try {
			await fetch(`${API_URL}/user/complete-tutorial`, {
				method: 'POST',
				credentials: 'include'
			});
			await refreshUserScraps();
			onComplete();
			goto('/dashboard', { invalidateAll: false });
		} catch {
			onComplete();
			goto('/dashboard', { invalidateAll: false });
		}
	}

	function handleBackdropClick(e: MouseEvent) {
		// Don't close on backdrop click when waiting for user to click a specific element
		if (currentStepData.waitForClick) return;
		if (e.target === e.currentTarget) {
			skip();
		}
	}

	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			skip();
		} else if (e.key === 'ArrowRight' || e.key === 'Enter') {
			nextStep();
		} else if (e.key === 'ArrowLeft' && currentStep > 0) {
			currentStep--;
		}
	}
</script>

<svelte:window onkeydown={handleKeydown} />

<div
	class="fixed inset-0 z-[100] flex items-center justify-center {highlightRect
		? 'pointer-events-none'
		: ''}"
	onclick={handleBackdropClick}
	onkeydown={(e) => e.key === 'Escape' && skip()}
	role="dialog"
	tabindex="-1"
>
	<!-- Dark overlay with cutout for highlighted element -->
	{#if highlightRect}
		<!-- Dark overlay using 4 divs around the spotlight to allow clicking through the cutout -->
		<div class="pointer-events-none absolute inset-0">
			<!-- Top -->
			<div
				class="pointer-events-auto absolute top-0 right-0 left-0 bg-black/75"
				style="height: {highlightRect.top - 8}px;"
			></div>
			<!-- Bottom -->
			<div
				class="pointer-events-auto absolute right-0 bottom-0 left-0 bg-black/75"
				style="top: {highlightRect.top + highlightRect.height + 8}px;"
			></div>
			<!-- Left -->
			<div
				class="pointer-events-auto absolute bg-black/75"
				style="top: {highlightRect.top - 8}px; left: 0; width: {highlightRect.left -
					8}px; height: {highlightRect.height + 16}px;"
			></div>
			<!-- Right -->
			<div
				class="pointer-events-auto absolute bg-black/75"
				style="top: {highlightRect.top - 8}px; right: 0; left: {highlightRect.left +
					highlightRect.width +
					8}px; height: {highlightRect.height + 16}px;"
			></div>
		</div>
		<!-- Highlight border -->
		<div
			class="pointer-events-none absolute animate-pulse rounded-2xl border-4 border-white"
			style="top: {highlightRect.top - 8}px; left: {highlightRect.left -
				8}px; width: {highlightRect.width + 16}px; height: {highlightRect.height + 16}px;"
		></div>
	{:else}
		<div class="absolute inset-0 bg-black/75"></div>
	{/if}

	<!-- Tutorial card -->
	<div
		data-tutorial-card
		class="pointer-events-auto w-full max-w-lg rounded-2xl border-4 border-black bg-white {currentStepData.highlight ===
		'create-project-modal'
			? 'z-[300]'
			: ''} {cardOffset ? 'fixed' : 'relative mx-4'} {!cardOffset && cardPosition === 'bottom'
			? 'mt-auto mb-8'
			: !cardOffset && cardPosition === 'bottom-center'
				? 'mt-auto mb-8'
				: !cardOffset && cardPosition === 'top'
					? 'mt-8 mb-auto'
					: !cardOffset && cardPosition === 'left'
						? 'mr-auto ml-8'
						: !cardOffset && cardPosition === 'right'
							? 'mr-8 ml-auto'
							: ''}"
		style={cardOffset ? `left: ${cardOffset.x}px; top: ${cardOffset.y}px;` : ''}
	>
		<!-- Drag handle -->
		<div
			onmousedown={handleDragStart}
			role="toolbar"
			class="flex cursor-move items-center justify-between border-b-2 border-dashed border-gray-200 px-6 pt-4 pb-2 select-none"
		>
			<div class="text-sm font-bold text-gray-500">{stepProgress}</div>
			<!-- Close button -->
			<button
				onclick={skip}
				class="cursor-pointer rounded-full p-2 transition-all duration-200 hover:bg-gray-100"
				aria-label={$t.tutorial.skipTutorial}
			>
				<X size={20} />
			</button>
		</div>

		<div class="p-6 pt-4">
			<!-- Progress dots -->
			<div class="mb-6 flex gap-1">
				{#each steps as _, i}
					<div
						class="h-1 flex-1 rounded-full transition-all duration-200 {i <= currentStep
							? 'bg-black'
							: 'bg-gray-200'}"
					></div>
				{/each}
			</div>

			<!-- Icon -->
			<div class="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-black text-white">
				{#if currentStep === 0}
					<Origami size={32} />
				{:else if currentStep === 1}
					<LayoutDashboard size={32} />
				{:else if currentStep === 2}
					<Clock size={32} />
				{:else if currentStep === 3}
					<Plus size={32} />
				{:else if currentStep === 4}
					<Gift size={32} />
				{:else if currentStep === 5}
					<Sparkles size={32} />
				{:else if currentStep === 6}
					<ShoppingBag size={32} />
				{:else if currentStep === 7}
					<Layers size={32} />
				{:else if currentStep === 8}
					<Flame size={32} />
				{:else if currentStep === 9}
					<Trophy size={32} />
				{:else}
					<Gift size={32} />
				{/if}
			</div>

			<!-- Title -->
			<h2 class="mb-2 text-2xl font-bold">{currentStepData.title}</h2>

			<!-- Description -->
			<p class="mb-6 text-gray-600">{currentStepData.description}</p>

			{#if currentStepData.highlight === null && currentStep === 2}
				<a
					href="https://hackatime.hackclub.com"
					target="_blank"
					rel="noopener noreferrer"
					class="mb-4 inline-block font-bold text-black underline hover:no-underline"
				>
					{$t.tutorial.setUpHackatime}
				</a>
			{/if}

			<!-- Buttons -->
			<div class="flex gap-3">
				<button
					onclick={skip}
					disabled={loading}
					class="cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{$t.tutorial.skip}
				</button>
				{#if currentStepData.waitForClick}
					<div
						class="flex flex-1 items-center justify-center gap-2 rounded-full bg-gray-200 px-4 py-2 font-bold text-gray-600"
					>
						<ArrowRight size={18} />
						<span>{$t.tutorial.clickToContinue}</span>
					</div>
				{:else if (currentStepData as { waitForEvent?: string }).waitForEvent}
					<div
						class="flex flex-1 items-center justify-center gap-2 rounded-full bg-gray-200 px-4 py-2 font-bold text-gray-600"
					>
						<ArrowRight size={18} />
						<span>{$t.tutorial.completeFormToContinue}</span>
					</div>
				{:else}
					<button
						onclick={nextStep}
						disabled={loading}
						class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
					>
						{#if loading}
							<span>{$t.tutorial.completing}</span>
						{:else if isLastStep}
							<Gift size={18} />
							<span>{$t.tutorial.claimScraps}</span>
						{:else}
							<span>{$t.tutorial.next}</span>
							<ArrowRight size={18} />
						{/if}
					</button>
				{/if}
			</div>
		</div>
	</div>
</div>
