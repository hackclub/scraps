<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		ArrowLeft,
		ChevronDown,
		Upload,
		X,
		Save,
		Check,
		Trash2,
		MessageSquare
	} from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import {
		formatHours,
		validateGithubUrl,
		validatePlayableUrl,
		parseHackatimeProjectNames
	} from '$lib/utils';
	import { invalidateAllStores } from '$lib/stores';
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
		tier: number;
		status: string;
		updateDescription: string | null;
		aiDescription: string | null;
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
	let saving = $state(false);
	let deleting = $state(false);
	let showDeleteConfirm = $state(false);
	let error = $state<string | null>(null);
	let imagePreview = $state<string | null>(null);
	let uploadingImage = $state(false);
	let hackatimeProjects = $state<HackatimeProject[]>([]);
	let _userSlackId = $state<string | null>(null);
	let selectedHackatimeNames = $state<string[]>([]);
	let loadingProjects = $state(false);
	let showDropdown = $state(false);
	let selectedTier = $state(1);
	let isUpdate = $state(false);
	let updateDescription = $state('');
	let usedAi = $state(false);
	let aiDescription = $state('');
	let reviewerNotes = $state('');

	const NAME_MAX = 50;
	const DESC_MIN = 20;
	const DESC_MAX = 1000;

	let hasDescription = $derived(
		(project?.description?.trim().length ?? 0) >= DESC_MIN &&
			(project?.description?.trim().length ?? 0) <= DESC_MAX
	);
	let hasName = $derived(
		(project?.name?.trim().length ?? 0) > 0 && (project?.name?.trim().length ?? 0) <= NAME_MAX
	);
	let githubValidation = $derived(validateGithubUrl(project?.githubUrl));
	let playableValidation = $derived(validatePlayableUrl(project?.playableUrl));
	let updateValid = $derived(!isUpdate || updateDescription.trim().length > 0);
	let aiValid = $derived(!usedAi || aiDescription.trim().length > 0);
	let canSave = $derived(
		hasDescription &&
			hasName &&
			githubValidation.valid &&
			playableValidation.valid &&
			updateValid &&
			aiValid
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
			project = responseData.project;
			imagePreview = project?.image || null;
			selectedTier = project?.tier || 1;
			isUpdate = !!project?.updateDescription;
			updateDescription = project?.updateDescription || '';
			usedAi = !!project?.aiDescription;
			aiDescription = project?.aiDescription || '';
			reviewerNotes = project?.reviewerNotes || '';
			if (project?.hackatimeProject) {
				selectedHackatimeNames = parseHackatimeProjectNames(project.hackatimeProject);
			}
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
				_userSlackId = apiData.slackId || null;
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

	async function handleSave() {
		if (!project || !canSave) return;

		saving = true;
		error = null;

		const hackatimeValue =
			selectedHackatimeNames.length > 0 ? selectedHackatimeNames.join(',') : null;

		try {
			const response = await fetch(`${API_URL}/projects/${project.id}`, {
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
					updateDescription: isUpdate ? updateDescription : null,
					aiDescription: usedAi ? aiDescription : null,
					reviewerNotes: reviewerNotes.trim() || null
				})
			});

			if (!response.ok) {
				const responseData = await response.json().catch(() => ({}));
				throw new Error(responseData.message || 'Failed to save project');
			}

			invalidateAllStores();
			goto(`/projects/${project.id}`);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save project';
		} finally {
			saving = false;
		}
	}

	async function handleDelete() {
		if (!project) return;

		deleting = true;
		error = null;

		try {
			const response = await fetch(`${API_URL}/projects/${project.id}`, {
				method: 'DELETE',
				credentials: 'include'
			});

			if (!response.ok) {
				const responseData = await response.json().catch(() => ({}));
				throw new Error(responseData.message || 'Failed to delete project');
			}

			invalidateAllStores();
			goto('/dashboard');
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to delete project';
			showDeleteConfirm = false;
		} finally {
			deleting = false;
		}
	}
</script>

<svelte:head>
	<title>edit {project?.name || 'project'} - scraps</title>
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
		<div class="rounded-2xl border-8 border-black bg-white p-6">
			<h1 class="mb-6 text-3xl font-bold">{$t.project.editProject}</h1>

			{#if error}
				<div class="mb-4 rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
					{error}
				</div>
			{/if}

			<div class="space-y-6">
				<!-- Image Upload -->
				<div>
					<label class="mb-2 block text-sm font-bold"
						>{$t.project.image} <span class="text-red-500">*</span></label
					>
					{#if imagePreview}
						<div class="relative h-48 w-full overflow-hidden rounded-lg border-2 border-black">
							<img
								src={imagePreview}
								alt="Preview"
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
							class="flex h-40 w-full cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed border-black transition-colors hover:bg-gray-50"
						>
							<Upload size={32} class="mb-2 text-gray-400" />
							<span class="text-sm text-gray-500">{$t.project.clickToUploadImage}</span>
							<input type="file" accept="image/*" onchange={handleImageUpload} class="hidden" />
						</label>
					{/if}
				</div>

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
						>{$t.project.githubUrl}
						<span class="text-gray-400">({$t.project.optional})</span></label
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
						>{$t.project.playableUrl}
						<span class="text-gray-400">({$t.project.requiredForSubmission})</span></label
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
						>{$t.project.hackatimeProject}
						<span class="text-gray-400">({$t.project.optional})</span></label
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
							class="flex w-full items-center justify-between rounded-lg border-2 border-black px-4 py-3 text-left focus:border-dashed focus:outline-none"
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

				<!-- Tier Selector -->
				<div>
					<label class="mb-2 block text-sm font-bold">{$t.project.projectTier}</label>
					<div class="grid grid-cols-2 gap-2">
						{#each TIERS as tier}
							<button
								type="button"
								onclick={() => (selectedTier = tier.value)}
								class="cursor-pointer rounded-lg border-2 border-black px-3 py-2 text-left font-bold transition-all duration-200 {selectedTier ===
								tier.value
									? 'bg-black text-white'
									: 'hover:border-dashed'}"
							>
								<span>{$t.project.tier.replace('{value}', String(tier.value))}</span>
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

				<!-- Is Update Checkbox -->
				<div>
					<label class="flex cursor-pointer items-center gap-3">
						<input
							type="checkbox"
							bind:checked={isUpdate}
							class="h-5 w-5 cursor-pointer accent-black"
						/>
						<span class="text-sm font-bold">{$t.project.isUpdateLabel}</span>
					</label>
				</div>

				{#if isUpdate}
					<div>
						<label for="updateDescription" class="mb-2 block text-sm font-bold"
							>{$t.project.whatDidYouUpdate} <span class="text-red-500">*</span></label
						>
						<textarea
							id="updateDescription"
							bind:value={updateDescription}
							rows="3"
							placeholder={$t.project.updateDescriptionPlaceholder}
							class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
						></textarea>
						{#if updateDescription.trim().length === 0}
							<p class="mt-1 text-xs text-red-500">{$t.project.pleaseDescribeUpdate}</p>
						{/if}
					</div>
				{/if}

				<!-- AI Usage Checkbox -->
				<div>
					<label class="flex cursor-pointer items-center gap-3">
						<input
							type="checkbox"
							bind:checked={usedAi}
							class="h-5 w-5 cursor-pointer accent-black"
						/>
						<span class="text-sm font-bold">{$t.project.usedAiLabel}</span>
					</label>
				</div>

				{#if usedAi}
					<div>
						<label for="aiDescription" class="mb-2 block text-sm font-bold"
							>{$t.project.howWasAiUsed} <span class="text-red-500">*</span></label
						>
						<textarea
							id="aiDescription"
							bind:value={aiDescription}
							rows="3"
							placeholder={$t.project.aiDescriptionPlaceholder}
							class="w-full resize-none rounded-lg border-2 border-black px-4 py-3 focus:border-dashed focus:outline-none"
						></textarea>
						{#if aiDescription.trim().length === 0}
							<p class="mt-1 text-xs text-red-500">{$t.project.pleaseDescribeAiUsage}</p>
						{/if}
					</div>
				{/if}
			</div>

			<!-- Notes for Reviewer -->
			<div class="mt-6">
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

			<!-- Actions -->
			<div class="mt-8 flex gap-4">
				<a
					href="/projects/{data.id}"
					class="flex w-1/2 cursor-pointer items-center justify-center rounded-full border-4 border-black px-4 py-3 text-center font-bold transition-all duration-200 hover:border-dashed"
				>
					{$t.common.cancel}
				</a>
				<button
					onclick={handleSave}
					disabled={saving || !canSave}
					class="flex w-1/2 cursor-pointer items-center justify-center gap-2 rounded-full bg-black px-4 py-3 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
				>
					<Save size={18} />
					{saving ? $t.project.saving : $t.project.saveChanges}
				</button>
			</div>

			<!-- Danger Zone -->
			<div class="mt-12 border-t-4 border-dashed border-gray-300 pt-8">
				<h2 class="mb-4 text-xl font-bold text-red-600">{$t.project.dangerZone}</h2>
				<div class="rounded-2xl border-4 border-red-500 p-6">
					<div class="flex items-center justify-between">
						<div>
							<h3 class="font-bold">{$t.project.deleteThisProject}</h3>
							<p class="text-sm text-gray-600">{$t.project.deleteWarning}</p>
						</div>
						<button
							onclick={() => (showDeleteConfirm = true)}
							class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-red-500 px-4 py-2 font-bold text-red-600 transition-all duration-200 hover:bg-red-50"
						>
							<Trash2 size={18} />
							{$t.common.delete}
						</button>
					</div>
				</div>
			</div>
		</div>

		<!-- Delete Confirmation Modal -->
		{#if showDeleteConfirm}
			<div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-6">
				<div class="w-full max-w-lg rounded-2xl border-4 border-black bg-white p-6">
					<h2 class="mb-4 text-2xl font-bold">{$t.project.areYouSure}</h2>
					<p class="mb-6 text-gray-700">
						{$t.project.deleteConfirmation.replace('{name}', project.name)}
					</p>
					<div class="flex gap-4">
						<button
							onclick={() => (showDeleteConfirm = false)}
							disabled={deleting}
							class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-3 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
						>
							{$t.common.cancel}
						</button>
						<button
							onclick={handleDelete}
							disabled={deleting}
							class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-red-600 bg-red-600 px-4 py-3 font-bold text-white transition-all duration-200 hover:bg-red-700 disabled:opacity-50"
						>
							<Trash2 size={18} />
							{deleting ? $t.project.deleting : $t.project.deleteProject}
						</button>
					</div>
				</div>
			</div>
		{/if}
	{/if}
</div>
