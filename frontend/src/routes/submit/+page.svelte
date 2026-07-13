<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { ChevronDown, Send } from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { formatHours } from '$lib/utils';
	import { t } from '$lib/i18n';

	interface Project {
		id: number;
		name: string;
		description: string;
		image: string | null;
		status: string;
		hours: number;
	}

	interface User {
		id: number;
		username: string;
		email: string;
		avatar: string | null;
		slackId: string | null;
		scraps: number;
		role: string;
	}

	let user = $state<User | null>(null);
	let projects = $state<Project[]>([]);
	let selectedProject = $state<Project | null>(null);
	let showDropdown = $state(false);
	let submitting = $state(false);
	let error = $state<string | null>(null);
	let _scraps = $derived(user?.scraps ?? 0);

	let feedbackSource = $state('');
	let feedbackGood = $state('');
	let feedbackImprove = $state('');

	let eligibleProjects = $derived(projects.filter((p) => p.status === 'in_progress'));

	onMount(async () => {
		user = await getUser();
		if (!user) {
			goto('/');
			return;
		}

		try {
			const response = await fetch(`${API_URL}/projects?limit=100`, {
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				if (data.data) {
					projects = data.data;
				}
			}
		} catch (e) {
			console.error('Failed to fetch projects:', e);
		}
	});

	async function submitProject() {
		if (!selectedProject) {
			error = $t.submit.pleaseSelectProject;
			return;
		}

		submitting = true;
		error = null;

		try {
			const response = await fetch(`${API_URL}/projects/${selectedProject.id}/submit`, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				credentials: 'include',
				body: JSON.stringify({
					feedbackSource,
					feedbackGood,
					feedbackImprove
				})
			});

			const data = await response.json();
			if (data.error) {
				throw new Error(data.error);
			}

			goto('/dashboard');
		} catch (e) {
			error = e instanceof Error ? e.message : $t.submit.failedToSubmit;
		} finally {
			submitting = false;
		}
	}
</script>

<svelte:head>
	<title>{$t.submit.pageTitle}</title>
</svelte:head>

<div class="mx-auto max-w-2xl px-6 pt-24 pb-24 md:px-12">
	<h1 class="mb-4 text-4xl font-bold md:text-5xl">{$t.submit.title}</h1>
	<p class="mb-8 text-lg text-gray-600">{$t.submit.subtitle}</p>

	{#if error}
		<div class="mb-6 rounded-lg border-2 border-red-500 bg-red-100 p-4 text-red-700">
			{error}
		</div>
	{/if}

	<div class="space-y-6">
		<div>
			<label class="mb-2 block text-sm font-bold">{$t.submit.selectProject}</label>
			<div class="relative">
				<button
					type="button"
					onclick={() => (showDropdown = !showDropdown)}
					class="flex w-full cursor-pointer items-center justify-between rounded-lg border-4 border-black px-4 py-3 text-left transition-all hover:border-dashed"
				>
					{#if selectedProject}
						<span class="font-bold">{selectedProject.name}</span>
					{:else}
						<span class="text-gray-500">{$t.submit.chooseProject}</span>
					{/if}
					<ChevronDown
						size={20}
						class={showDropdown ? 'rotate-180 transition-transform' : 'transition-transform'}
					/>
				</button>

				{#if showDropdown}
					<div
						class="absolute top-full right-0 left-0 z-10 mt-2 max-h-64 overflow-y-auto rounded-lg border-4 border-black bg-white"
					>
						{#if eligibleProjects.length === 0}
							<div class="px-4 py-3 text-gray-500">{$t.submit.noEligibleProjects}</div>
						{:else}
							{#each eligibleProjects as project}
								<button
									type="button"
									onclick={() => {
										selectedProject = project;
										showDropdown = false;
									}}
									class="flex w-full cursor-pointer items-center justify-between px-4 py-3 text-left transition-colors hover:bg-gray-100"
								>
									<span class="font-bold">{project.name}</span>
									<span class="text-sm text-gray-500">{formatHours(project.hours)}h</span>
								</button>
							{/each}
						{/if}
					</div>
				{/if}
			</div>
		</div>

		{#if selectedProject}
			<div class="rounded-2xl border-4 border-black p-6">
				<h3 class="mb-2 text-xl font-bold">{selectedProject.name}</h3>
				<p class="mb-4 text-gray-600">{selectedProject.description}</p>
				<div class="flex items-center gap-4 text-sm">
					<span class="rounded-full bg-gray-100 px-3 py-1 font-bold"
						>{$t.submit.hoursLogged.replace('{hours}', formatHours(selectedProject.hours))}</span
					>
					<span class="rounded-full bg-gray-100 px-3 py-1 font-bold">{selectedProject.status}</span>
				</div>
			</div>

			<!-- Feedback Questions -->
			<div>
				<label for="feedbackSource" class="mb-2 block text-sm font-bold"
					>{$t.submit.feedbackSourceLabel}</label
				>
				<textarea
					id="feedbackSource"
					bind:value={feedbackSource}
					rows="3"
					placeholder={$t.submit.feedbackSourcePlaceholder}
					class="w-full resize-none rounded-lg border-4 border-black px-4 py-3 transition-all focus:border-dashed focus:outline-none"
				></textarea>
			</div>

			<div>
				<label for="feedbackGood" class="mb-2 block text-sm font-bold"
					>{$t.submit.feedbackGoodLabel}</label
				>
				<textarea
					id="feedbackGood"
					bind:value={feedbackGood}
					rows="3"
					placeholder={$t.submit.feedbackGoodPlaceholder}
					class="w-full resize-none rounded-lg border-4 border-black px-4 py-3 transition-all focus:border-dashed focus:outline-none"
				></textarea>
			</div>

			<div>
				<label for="feedbackImprove" class="mb-2 block text-sm font-bold"
					>{$t.submit.feedbackImproveLabel}</label
				>
				<textarea
					id="feedbackImprove"
					bind:value={feedbackImprove}
					rows="3"
					placeholder={$t.submit.feedbackImprovePlaceholder}
					class="w-full resize-none rounded-lg border-4 border-black px-4 py-3 transition-all focus:border-dashed focus:outline-none"
				></textarea>
			</div>
		{/if}

		<button
			onclick={submitProject}
			disabled={submitting || !selectedProject}
			class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full bg-black px-6 py-4 text-lg font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
		>
			<Send size={20} />
			<span>{submitting ? $t.submit.submitting : $t.submit.submitForReview}</span>
		</button>
	</div>
</div>
