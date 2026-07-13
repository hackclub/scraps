<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		ArrowLeft,
		Send,
		Check,
		ChevronDown,
		Upload,
		X,
		RefreshCw,
		Bot,
		MessageSquare
	} from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { formatHours, validateGithubUrl, validatePlayableUrl } from '$lib/utils';
	import { t } from '$lib/i18n';

	let { data } = $props();

	interface Project {
		id: number;
		userId: string;
		name: string;
		description: string;
		image: string | null;
		githubUrl: string | null;
		playableUrl: string | null;
		hackatimeProject: string | null;
		hours: number;
		status: string;
		tier: number;
		reviewerNotes: string | null;
	}

	const TIERS = [
		{ value: 1, descriptionKey: 'tier1' as const },
		{ value: 2, descriptionKey: 'tier2' as const },
		{ value: 3, descriptionKey: 'tier3' as const },
		{ value: 4, descriptionKey: 'tier4' as const }
	];

	interface HackatimeProject {
		name: string;
		hours: number;
		repoUrl: string | null;
		languages: string[];
	}

	let project = $state<Project | null>(null);
	let loading = $state(true);
	let submitting = $state(false);
	let error = $state<string | null>(null);
	let imagePreview = $state<string | null>(null);
	let uploadingImage = $state(false);
	let hackatimeProjects = $state<HackatimeProject[]>([]);
	let userSlackId = $state<string | null>(null);
	let selectedHackatimeNames = $state<string[]>([]);
	let loadingProjects = $state(false);
	let showDropdown = $state(false);
	let selectedTier = $state(1);
	let feedbackSource = $state('');
	let feedbackGood = $state('');
	let feedbackImprove = $state('');
	let hasSubmittedFeedbackBefore = $state(false);
	let isShippedUpdate = $state(false);
	let updateDescription = $state('');
	let usedAi = $state(false);
	let aiDescription = $state('');
	let reviewerNotes = $state('');

	const NAME_MAX = 50;
	const DESC_MIN = 20;
	const DESC_MAX = 1000;

	let hasImage = $derived(!!project?.image);
	let hasHackatime = $derived(selectedHackatimeNames.length > 0);
	let githubValidation = $derived(validateGithubUrl(project?.githubUrl));
	let playableValidation = $derived(validatePlayableUrl(project?.playableUrl));
	let hasGithub = $derived(!!project?.githubUrl?.trim() && githubValidation.valid);
	let hasPlayableUrl = $derived(!!project?.playableUrl?.trim() && playableValidation.valid);
	let hasDescription = $derived(
		(project?.description?.trim().length ?? 0) >= DESC_MIN &&
			(project?.description?.trim().length ?? 0) <= DESC_MAX
	);
	let hasName = $derived(
		(project?.name?.trim().length ?? 0) > 0 && (project?.name?.trim().length ?? 0) <= NAME_MAX
	);
	let hasFeedback = $derived(
		hasSubmittedFeedbackBefore ||
			(feedbackSource.trim().length > 0 &&
				feedbackGood.trim().length > 0 &&
				feedbackImprove.trim().length > 0)
	);
	let hasUpdateDescription = $derived(!isShippedUpdate || updateDescription.trim().length > 0);
	let hasAiDescription = $derived(!usedAi || aiDescription.trim().length > 0);
	let allRequirementsMet = $derived(
		hasImage &&
			hasHackatime &&
			hasGithub &&
			hasPlayableUrl &&
			hasDescription &&
			hasName &&
			hasFeedback &&
			hasUpdateDescription &&
			hasAiDescription
	);

	onMount(async () => {
		const user = await getUser();
		if (!user) {
			goto('/');
			return;
		}

		try {
			const response = await fetch(`${API_URL}/projects/${data.id}`, {
				credentials: 'include'
			});
			if (!response.ok) {
				throw new Error('Project not found');
			}
			const responseData = await response.json();
			if (responseData.error) {
				throw new Error(responseData.error);
			}
			if (!responseData.isOwner) {
				throw new Error('You can only submit your own projects');
			}
			project = responseData.project;
			imagePreview = project?.image || null;
			hasSubmittedFeedbackBefore = responseData.hasSubmittedFeedback ?? false;
			isShippedUpdate = project?.status === 'shipped';
			reviewerNotes = project?.reviewerNotes || '';
			if (project?.hackatimeProject) {
				selectedHackatimeNames = project.hackatimeProject
					.split(',')
					.map((p: string) => {
						const trimmed = p.trim();
						const slashIndex = trimmed.indexOf('/');
						return slashIndex !== -1 ? trimmed.substring(slashIndex + 1) : trimmed;
					})
					.filter((p: string) => p.length > 0);
			}
			selectedTier = project?.tier ?? 1;
			fetchHackatimeProjects();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load project';
		} finally {
			loading = false;
		}
	});

	async function fetchHackatimeProjects() {
		loadingProjects = true;
		try {
			const response = await fetch(`${API_URL}/hackatime/projects`, {
				credentials: 'include'
			});
			if (response.ok) {
				const apiData = await response.json();
				hackatimeProjects = apiData.projects || [];
				userSlackId = apiData.slackId || null;
			}
		} catch (e) {
			console.error('Failed to fetch hackatime projects:', e);
		} finally {
			loadingProjects = false;
		}
	}

	async function handleImageUpload(event: Event) {
		const input = event.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file || !project) return;

		if (file.size > 5 * 1024 * 1024) {
			error = $t.project.imageMustBeLessThan;
			return;
		}

		imagePreview = URL.createObjectURL(file);
		uploadingImage = true;
		error = null;

		try {
			const formData = new FormData();
			formData.append('file', file);

			const response = await fetch(`${API_URL}/upload/image`, {
				method: 'POST',
				credentials: 'include',
				body: formData
			});

			const responseData = await response.json();
			if (responseData.error) {
				throw new Error(responseData.error);
			}

			project.image = responseData.url;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to upload image';
			imagePreview = project?.image || null;
		} finally {
			uploadingImage = false;
		}
	}

	function removeImage() {
		if (project) {
			project.image = null;
		}
		imagePreview = null;
	}

	function selectHackatimeProject(hp: HackatimeProject) {
		if (project) {
			const idx = selectedHackatimeNames.indexOf(hp.name);
			if (idx >= 0) {
				selectedHackatimeNames = selectedHackatimeNames.filter((_, i) => i !== idx);
			} else {
				selectedHackatimeNames = [...selectedHackatimeNames, hp.name];
			}
			// Recalculate total hours from all selected projects
			const totalHours = selectedHackatimeNames.reduce((sum, name) => {
				const found = hackatimeProjects.find((p) => p.name === name);
				return sum + (found?.hours || 0);
			}, 0);
			project.hours = Math.round(totalHours * 10) / 10;
			if (hp.repoUrl && !project.githubUrl) {
				project.githubUrl = hp.repoUrl;
			}
		}
	}

	function removeHackatimeProject(name: string) {
		selectedHackatimeNames = selectedHackatimeNames.filter((n) => n !== name);
		if (project) {
			const totalHours = selectedHackatimeNames.reduce((sum, n) => {
				const found = hackatimeProjects.find((p) => p.name === n);
				return sum + (found?.hours || 0);
			}, 0);
			project.hours = Math.round(totalHours * 10) / 10;
		}
	}

	async function handleSubmit() {
		if (!project || !allRequirementsMet) return;

		submitting = true;
		error = null;

		const hackatimeValue =
			selectedHackatimeNames.length > 0
				? selectedHackatimeNames
						.map((name) => (userSlackId ? `${userSlackId}/${name}` : name))
						.join(',')
				: null;

		try {
			// First update the project with any changes
			const updateResponse = await fetch(`${API_URL}/projects/${project.id}`, {
				method: 'PUT',
				headers: {
					'Content-Type': 'application/json'
				},
				credentials: 'include',
				body: JSON.stringify({
					name: project.name,
					description: project.description,
					image: project.image,
					githubUrl: project.githubUrl,
					playableUrl: project.playableUrl,
					hackatimeProject: hackatimeValue,
					tier: selectedTier,
					updateDescription: isShippedUpdate ? updateDescription : null,
					aiDescription: usedAi ? aiDescription : null,
					reviewerNotes: reviewerNotes.trim() || null
				})
			});

			if (!updateResponse.ok) {
				const responseData = await updateResponse.json().catch(() => ({}));
				throw new Error(responseData.message || 'Failed to update project');
			}

			// Then submit for review
			const submitResponse = await fetch(`${API_URL}/projects/${project.id}/submit`, {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				credentials: 'include',
				body: JSON.stringify({
					feedbackSource,
					feedbackGood,
					feedbackImprove
				})
			});

			const submitData = await submitResponse.json().catch(() => ({}));

			if (submitData.error === 'ineligible' && submitData.redirectTo) {
				goto(submitData.redirectTo);
				return;
			}

			if (!submitResponse.ok) {
				throw new Error(submitData.message || 'Failed to submit project');
			}

			goto(`/projects/${project.id}`);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to submit project';
		} finally {
			submitting = false;
		}
	}
</script>

<svelte:head>
	<title>{isShippedUpdate ? 'ship update' : 'submit'} {project?.name || 'project'} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	<a
		href="/projects/{data.id}"
		class="mb-8 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
	>
		<ArrowLeft size={20} />
		{$t.project.backToProject}
	</a>

	{#if loading}
		<div class="py-12 text-center">
			<p class="text-lg text-gray-500">{$t.project.loadingProject}</p>
		</div>
	{:else if error && !project}
		<div class="py-12 text-center">
			<p class="text-lg text-red-600">{error}</p>
			<a href="/dashboard" class="mt-4 inline-block font-bold underline">{$t.project.goBack}</a>
		</div>
	{:else if project}
		<div class="rounded-2xl border-4 border-black bg-white p-6">
			<h1 class="mb-2 text-3xl font-bold">
				{isShippedUpdate ? 'ship update' : $t.project.submitForReview}
			</h1>
			<p class="mb-6 text-gray-600">
				{isShippedUpdate
					? "submit your updated project for review. you'll earn the difference in scraps based on your new hours."
					: $t.project.submitRequirementsHint}
			</p>

			{#if error}
				<div class="mb-4 rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
					{error}
				</div>
			{/if}

			<!-- Project Image Upload -->
			<div class="mb-6">
				<label class="mb-2 block text-sm font-bold"
					>{$t.project.projectImage} <span class="text-red-500">*</span></label
				>
				{#if imagePreview}
					<div class="relative h-48 w-full overflow-hidden rounded-lg border-2 border-black">
						<img
							src={imagePreview}
							alt={project.name}
							class="h-full w-full bg-gray-100 object-contain"
						/>
						{#if uploadingImage}
							<div class="absolute inset-0 flex items-center justify-center bg-black/50">
								<span class="font-bold text-white">{$t.project.uploading}</span>
							</div>
						{:else}
							<button
								type="button"
								onclick={removeImage}
								class="absolute top-2 right-2 cursor-pointer rounded-full border-2 border-black bg-white p-1 hover:bg-gray-100"
							>
								<X size={16} />
							</button>
						{/if}
					</div>
				{:else}
					<label
						class="flex h-48 w-full cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed border-black transition-colors hover:bg-gray-50"
					>
						<Upload size={32} class="mb-2 text-gray-400" />
						<span class="text-sm text-gray-500">{$t.project.clickToUploadImage}</span>
						<input type="file" accept="image/*" onchange={handleImageUpload} class="hidden" />
					</label>
				{/if}
			</div>

			<!-- Editable Fields -->
			<div class="mb-6 space-y-4">
				<!-- Name -->
				<div>
					<label for="name" class="mb-2 block text-sm font-bold"
						>{$t.project.name} <span class="text-red-500">*</span></label
					>
					<input
						id="name"
						type="text"
						bind:value={project.name}
						maxlength={NAME_MAX}
						class="w-full rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
					/>
					<p class="mt-1 text-right text-xs text-gray-500">{project.name.length}/{NAME_MAX}</p>
				</div>

				<!-- Description -->
				<div>
					<label for="description" class="mb-2 block text-sm font-bold"
						>{$t.project.description} <span class="text-red-500">*</span></label
					>
					<textarea
						id="description"
						bind:value={project.description}
						rows="4"
						maxlength={DESC_MAX}
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
					></textarea>
					<p
						class="mt-1 text-right text-xs {project.description.length < DESC_MIN
							? 'text-red-500'
							: 'text-gray-500'}"
					>
						{project.description.length}/{DESC_MAX} (min {DESC_MIN})
					</p>
				</div>

				<!-- GitHub URL -->
				<div>
					<label for="githubUrl" class="mb-2 block text-sm font-bold"
						>{$t.project.githubUrl} <span class="text-red-500">*</span></label
					>
					<input
						id="githubUrl"
						type="url"
						bind:value={project.githubUrl}
						placeholder="https://github.com/user/repo"
						class="w-full rounded-lg border-2 px-4 py-3 focus:border-dashed focus:outline-none {project.githubUrl?.trim() &&
						!githubValidation.valid
							? 'border-red-500'
							: 'border-black'}"
					/>
					{#if project.githubUrl?.trim() && !githubValidation.valid}
						<p class="mt-1 text-xs text-red-500">{githubValidation.error}</p>
					{/if}
				</div>

				<!-- Playable URL -->
				<div>
					<label for="playableUrl" class="mb-2 block text-sm font-bold"
						>{$t.project.playableUrl} <span class="text-red-500">*</span></label
					>
					<input
						id="playableUrl"
						type="url"
						bind:value={project.playableUrl}
						placeholder="https://yourproject.com or https://replit.com/..."
						class="w-full rounded-lg border-2 px-4 py-3 focus:border-dashed focus:outline-none {project.playableUrl?.trim() &&
						!playableValidation.valid
							? 'border-red-500'
							: 'border-black'}"
					/>
					{#if project.playableUrl?.trim() && !playableValidation.valid}
						<p class="mt-1 text-xs text-red-500">{playableValidation.error}</p>
					{:else}
						<p class="mt-1 text-xs text-gray-500">{$t.project.playableUrlHint}</p>
					{/if}
				</div>

				<!-- Hackatime Project Dropdown -->
				<div>
					<label class="mb-2 block text-sm font-bold"
						>{$t.project.hackatimeProject} <span class="text-red-500">*</span></label
					>
					{#if selectedHackatimeNames.length > 0}
						<div class="mb-2 flex flex-wrap gap-2">
							{#each selectedHackatimeNames as name}
								{@const hp = hackatimeProjects.find((p) => p.name === name)}
								<span
									class="flex items-center gap-1 rounded-full border-2 border-black bg-gray-100 px-3 py-1 text-sm font-medium"
								>
									{name}
									{#if hp}
										<span class="text-gray-500">({formatHours(hp.hours)}h)</span>
									{/if}
									<button
										type="button"
										onclick={() => removeHackatimeProject(name)}
										class="ml-1 cursor-pointer rounded-full hover:bg-gray-200"
									>
										<X size={14} />
									</button>
								</span>
							{/each}
						</div>
					{/if}
					<div class="relative">
						<button
							type="button"
							onclick={() => (showDropdown = !showDropdown)}
							class="flex w-full cursor-pointer items-center justify-between rounded-lg border-2 border-black px-4 py-3 text-left focus:border-dashed focus:outline-none"
						>
							{#if loadingProjects}
								<span class="text-gray-500">{$t.project.loadingProjects}</span>
							{:else if selectedHackatimeNames.length > 0}
								<span class="text-gray-500">add another project...</span>
							{:else}
								<span class="text-gray-500">{$t.project.selectAProject}</span>
							{/if}
							<ChevronDown
								size={20}
								class={showDropdown ? 'rotate-180 transition-transform' : 'transition-transform'}
							/>
						</button>

						{#if showDropdown && !loadingProjects}
							<div
								class="absolute top-full right-0 left-0 z-10 mt-1 max-h-48 overflow-y-auto rounded-lg border-2 border-black bg-white"
							>
								{#if hackatimeProjects.length === 0}
									<div class="px-4 py-2 text-sm text-gray-500">{$t.project.noProjectsFound}</div>
								{:else}
									{#each hackatimeProjects as hp}
										{@const isSelected = selectedHackatimeNames.includes(hp.name)}
										<button
											type="button"
											onclick={() => selectHackatimeProject(hp)}
											class="flex w-full cursor-pointer items-center justify-between px-4 py-2 text-left hover:bg-gray-100 {isSelected
												? 'bg-gray-50'
												: ''}"
										>
											<span class="flex items-center gap-2">
												{#if isSelected}
													<Check size={16} class="text-green-600" />
												{/if}
												<span class="font-medium">{hp.name}</span>
											</span>
											<span class="text-sm text-gray-500">{formatHours(hp.hours)}h</span>
										</button>
									{/each}
								{/if}
							</div>
						{/if}
					</div>
				</div>
			</div>

			<!-- Tier Selection -->
			<div class="mb-6">
				<label class="mb-2 block text-sm font-bold"
					>{$t.project.projectTier} <span class="text-red-500">*</span></label
				>
				<p class="mb-3 text-xs text-gray-500">
					{$t.project.selectComplexityTier}
				</p>
				<div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
					{#each TIERS as tier}
						<button
							type="button"
							onclick={() => (selectedTier = tier.value)}
							class="cursor-pointer rounded-full border-4 border-black px-4 py-3 text-left font-bold transition-all duration-200 {selectedTier ===
							tier.value
								? 'bg-black text-white'
								: 'hover:border-dashed'}"
						>
							<div class="flex items-center justify-between">
								<span>{$t.project.tier.replace('{value}', String(tier.value))}</span>
							</div>
							<p
								class="mt-1 text-xs {selectedTier === tier.value
									? 'text-gray-300'
									: 'text-gray-500'}"
							>
								{$t.project.tierDescriptions[tier.descriptionKey]}
							</p>
						</button>
					{/each}
				</div>
			</div>

			<!-- Update Description (required for shipped project updates) -->
			{#if isShippedUpdate}
				<div class="mb-6 rounded-lg border-2 border-dashed border-gray-400 bg-gray-50 p-4">
					<p class="mb-3 flex items-center gap-1.5 text-sm font-bold text-gray-600">
						<RefreshCw size={14} />
						this is an update to a shipped project
					</p>
					<div>
						<label for="updateDescription" class="mb-2 block text-sm font-bold"
							>what did you update? <span class="text-red-500">*</span></label
						>
						<textarea
							id="updateDescription"
							bind:value={updateDescription}
							rows="3"
							placeholder="describe what you changed or added since the last ship..."
							class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
						></textarea>
						{#if updateDescription.trim().length === 0}
							<p class="mt-1 text-xs text-red-500">please describe what you updated</p>
						{/if}
					</div>
				</div>
			{/if}

			<!-- AI Usage -->
			<div class="mb-6 space-y-4">
				<label class="flex cursor-pointer items-center gap-3">
					<input
						type="checkbox"
						bind:checked={usedAi}
						class="h-5 w-5 cursor-pointer accent-black"
					/>
					<span class="text-sm font-bold">i used ai in this project</span>
				</label>
				{#if usedAi}
					<div class="rounded-lg border-2 border-dashed border-purple-400 bg-purple-50 p-4">
						<p class="mb-2 flex items-center gap-1.5 text-sm font-bold text-purple-600">
							<Bot size={14} />
							how was ai used? <span class="text-red-500">*</span>
						</p>
						<textarea
							bind:value={aiDescription}
							rows="3"
							placeholder="describe how you used ai in this project..."
							class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
						></textarea>
						{#if aiDescription.trim().length === 0}
							<p class="mt-1 text-xs text-red-500">please describe how ai was used</p>
						{/if}
					</div>
				{/if}
			</div>

			<!-- Notes for Reviewer -->
			<div class="mb-6">
				<label for="reviewerNotes" class="mb-2 flex items-center gap-1.5 text-sm font-bold">
					<MessageSquare size={14} />
					notes for reviewer
					<span class="text-gray-400">(optional)</span>
				</label>
				<textarea
					id="reviewerNotes"
					bind:value={reviewerNotes}
					rows="3"
					placeholder="anything you'd like the reviewer to know about this project..."
					class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
				></textarea>
			</div>

			<!-- Feedback -->
			<div class="mb-6 space-y-4">
				<div>
					<label for="feedbackSource" class="mb-2 block text-sm font-bold"
						>{$t.submit.feedbackSourceLabel}
						{#if !hasSubmittedFeedbackBefore}<span class="text-red-500">*</span>{/if}
					</label>
					<textarea
						id="feedbackSource"
						bind:value={feedbackSource}
						rows="2"
						placeholder={$t.submit.feedbackSourcePlaceholder}
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
					></textarea>
				</div>
				<div>
					<label for="feedbackGood" class="mb-2 block text-sm font-bold"
						>{$t.submit.feedbackGoodLabel}
						{#if !hasSubmittedFeedbackBefore}<span class="text-red-500">*</span>{/if}
					</label>
					<textarea
						id="feedbackGood"
						bind:value={feedbackGood}
						rows="2"
						placeholder={$t.submit.feedbackGoodPlaceholder}
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
					></textarea>
				</div>
				<div>
					<label for="feedbackImprove" class="mb-2 block text-sm font-bold"
						>{$t.submit.feedbackImproveLabel}
						{#if !hasSubmittedFeedbackBefore}<span class="text-red-500">*</span>{/if}
					</label>
					<textarea
						id="feedbackImprove"
						bind:value={feedbackImprove}
						rows="2"
						placeholder={$t.submit.feedbackImprovePlaceholder}
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
					></textarea>
				</div>
			</div>

			<!-- Requirements Checklist -->
			<div class="mb-6 rounded-lg border-2 border-black p-4">
				<p class="mb-3 font-bold">{$t.project.requirementsChecklist}</p>
				<ul class="space-y-2">
					<li class="flex items-center gap-2 text-sm">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasImage
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasImage}<Check size={12} />{/if}
						</span>
						<span class={hasImage ? '' : 'text-gray-500'}>{$t.project.projectImageUploaded}</span>
					</li>
					<li class="flex items-center gap-2 text-sm">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasName
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasName}<Check size={12} />{/if}
						</span>
						<span class={hasName ? '' : 'text-gray-500'}
							>{$t.project.projectName.replace('{max}', String(NAME_MAX))}</span
						>
					</li>
					<li class="flex items-center gap-2 text-sm">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasDescription
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasDescription}<Check size={12} />{/if}
						</span>
						<span class={hasDescription ? '' : 'text-gray-500'}
							>{$t.project.descriptionRequirement
								.replace('{min}', String(DESC_MIN))
								.replace('{max}', String(DESC_MAX))}</span
						>
					</li>
					<li class="flex items-center gap-2 text-sm">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasGithub
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasGithub}<Check size={12} />{/if}
						</span>
						<span class={hasGithub ? '' : 'text-gray-500'}>{$t.project.githubRepositoryLinked}</span
						>
					</li>
					<li class="flex items-center gap-2 text-sm">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasPlayableUrl
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasPlayableUrl}<Check size={12} />{/if}
						</span>
						<span class={hasPlayableUrl ? '' : 'text-gray-500'}
							>{$t.project.playableUrlProvided}</span
						>
					</li>
					<li class="flex items-center gap-2 text-sm">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasHackatime
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasHackatime}<Check size={12} />{/if}
						</span>
						<span class={hasHackatime ? '' : 'text-gray-500'}
							>{$t.project.hackatimeProjectSelected}</span
						>
					</li>
					{#if isShippedUpdate}
						<li class="flex items-center gap-2 text-sm">
							<span
								class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasUpdateDescription
									? 'bg-black text-white'
									: ''}"
							>
								{#if hasUpdateDescription}<Check size={12} />{/if}
							</span>
							<span class={hasUpdateDescription ? '' : 'text-gray-500'}
								>update description provided</span
							>
						</li>
					{/if}
					{#if usedAi}
						<li class="flex items-center gap-2 text-sm">
							<span
								class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasAiDescription
									? 'bg-black text-white'
									: ''}"
							>
								{#if hasAiDescription}<Check size={12} />{/if}
							</span>
							<span class={hasAiDescription ? '' : 'text-gray-500'}>ai usage described</span>
						</li>
					{/if}
					{#if !hasSubmittedFeedbackBefore}
						<li class="flex items-center gap-2 text-sm">
							<span
								class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasFeedback
									? 'bg-black text-white'
									: ''}"
							>
								{#if hasFeedback}<Check size={12} />{/if}
							</span>
							<span class={hasFeedback ? '' : 'text-gray-500'}>{$t.project.feedbackCompleted}</span>
						</li>
					{/if}
				</ul>
			</div>

			<!-- Actions -->
			<div class="flex gap-4">
				<a
					href="/projects/{data.id}"
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-3 text-center font-bold transition-all duration-200 hover:border-dashed"
				>
					{$t.common.cancel}
				</a>
				<button
					onclick={handleSubmit}
					disabled={submitting || !allRequirementsMet}
					class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full bg-black px-4 py-3 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
				>
					{#if isShippedUpdate}
						<RefreshCw size={18} />
					{:else}
						<Send size={18} />
					{/if}
					{submitting
						? $t.project.submitting
						: isShippedUpdate
							? 'ship update'
							: $t.project.submitForReview}
				</button>
			</div>
		</div>
	{/if}
</div>
