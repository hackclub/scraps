<script lang="ts">
	import { X, ChevronDown, Upload, Check } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { formatHours } from '$lib/utils';
	import { tutorialProjectIdStore, type Project } from '$lib/stores';
	import { goto } from '$app/navigation';
	import { t } from '$lib/i18n';

	interface HackatimeProject {
		name: string;
		hours: number;
		repoUrl: string | null;
		languages: string[];
	}

	let {
		open,
		onClose,
		onCreated,
		tutorialMode = false
	}: {
		open: boolean;
		onClose: () => void;
		onCreated: (project: Project) => void;
		tutorialMode?: boolean;
	} = $props();

	let name = $state('');
	let description = $state('');

	// Pre-fill values when modal opens in tutorial mode
	$effect(() => {
		if (open && tutorialMode && name === '' && description === '') {
			name = 'my first scrap';
			description =
				"this is my first project on scraps! i'm excited to start building and earning rewards.";
		}
	});
	let githubUrl = $state('');
	let imageUrl = $state<string | null>(null);
	let imagePreview = $state<string | null>(null);
	let uploadingImage = $state(false);
	let selectedHackatimeProjects = $state<HackatimeProject[]>([]);
	let hackatimeProjects = $state<HackatimeProject[]>([]);
	let _userSlackId = $state<string | null>(null);
	let loadingProjects = $state(false);
	let showDropdown = $state(false);
	let loading = $state(false);
	let error = $state<string | null>(null);
	let selectedTier = $state(1);
	let isUpdate = $state(false);
	let updateDescription = $state('');
	let usedAi = $state(false);
	let aiDescription = $state('');

	const TIERS = [
		{ value: 1, description: $t.createProject.tierDescriptions.tier1 },
		{ value: 2, description: $t.createProject.tierDescriptions.tier2 },
		{ value: 3, description: $t.createProject.tierDescriptions.tier3 },
		{ value: 4, description: $t.createProject.tierDescriptions.tier4 }
	];

	const NAME_MAX = 50;
	const DESC_MIN = 20;
	const DESC_MAX = 1000;

	let _hasImage = $derived(!!imageUrl);
	let _hasHackatime = $derived(selectedHackatimeProjects.length > 0);
	let hasDescription = $derived(
		description.trim().length >= DESC_MIN && description.trim().length <= DESC_MAX
	);
	let hasName = $derived(name.trim().length > 0 && name.trim().length <= NAME_MAX);
	let updateValid = $derived(!isUpdate || updateDescription.trim().length > 0);
	let aiValid = $derived(!usedAi || aiDescription.trim().length > 0);
	let allRequirementsMet = $derived(hasDescription && hasName && updateValid && aiValid);

	async function fetchHackatimeProjects() {
		loadingProjects = true;
		try {
			const response = await fetch(`${API_URL}/hackatime/projects`, {
				credentials: 'include'
			});
			if (response.ok) {
				const data = await response.json();
				hackatimeProjects = data.projects || [];
				_userSlackId = data.slackId || null;
			}
		} catch (e) {
			console.error('Failed to fetch hackatime projects:', e);
		} finally {
			loadingProjects = false;
		}
	}

	$effect(() => {
		if (open) {
			fetchHackatimeProjects();
		}
	});

	async function handleImageUpload(event: Event) {
		const input = event.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;

		if (file.size > 5 * 1024 * 1024) {
			error = $t.createProject.imageMustBeLessThan;
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

			const data = await response.json();
			if (data.error) {
				throw new Error(data.error);
			}

			imageUrl = data.url;
		} catch (e) {
			error = e instanceof Error ? e.message : $t.createProject.failedToCreateProject;
			imagePreview = null;
		} finally {
			uploadingImage = false;
		}
	}

	function removeImage() {
		imageUrl = null;
		imagePreview = null;
	}

	function selectProject(project: HackatimeProject) {
		const idx = selectedHackatimeProjects.findIndex((p) => p.name === project.name);
		if (idx >= 0) {
			selectedHackatimeProjects = selectedHackatimeProjects.filter((_, i) => i !== idx);
		} else {
			selectedHackatimeProjects = [...selectedHackatimeProjects, project];
		}
		// Always update GitHub URL from hackatime project if available
		if (project.repoUrl && !githubUrl) {
			githubUrl = project.repoUrl;
		}
	}

	function removeSelectedProject(name: string) {
		selectedHackatimeProjects = selectedHackatimeProjects.filter((p) => p.name !== name);
	}

	function resetForm() {
		name = '';
		description = '';
		githubUrl = '';
		imageUrl = null;
		imagePreview = null;
		selectedHackatimeProjects = [];
		showDropdown = false;
		selectedTier = 1;
		isUpdate = false;
		updateDescription = '';
		usedAi = false;
		aiDescription = '';
		error = null;
	}

	async function handleSubmit() {
		if (!allRequirementsMet) {
			error = $t.createProject.pleaseCompleteRequirements;
			return;
		}

		loading = true;
		error = null;

		const hackatimeValue =
			selectedHackatimeProjects.length > 0
				? selectedHackatimeProjects.map((p) => p.name).join(',')
				: null;
		const finalGithubUrl = githubUrl.trim() || selectedHackatimeProjects[0]?.repoUrl || null;

		try {
			const response = await fetch(`${API_URL}/projects`, {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				credentials: 'include',
				body: JSON.stringify({
					name,
					description,
					image: imageUrl || null,
					githubUrl: finalGithubUrl,
					hackatimeProject: hackatimeValue,
					tier: selectedTier,
					updateDescription: isUpdate ? updateDescription : null,
					aiDescription: usedAi ? aiDescription : null
				})
			});

			if (!response.ok) {
				const data = await response.json().catch(() => ({}));
				throw new Error(data.message || $t.createProject.failedToCreateProject);
			}

			const newProject = await response.json();
			resetForm();
			if (tutorialMode) {
				tutorialProjectIdStore.set(newProject.id);
				window.dispatchEvent(new CustomEvent('tutorial:project-created'));
				onCreated(newProject);
				goto(`/projects/${newProject.id}`, { invalidateAll: false });
			} else {
				onCreated(newProject);
			}
		} catch (e) {
			error = e instanceof Error ? e.message : $t.createProject.failedToCreateProject;
		} finally {
			loading = false;
		}
	}

	function handleClose() {
		resetForm();
		onClose();
	}

	function handleBackdropClick(e: MouseEvent) {
		if (tutorialMode) return;
		if (e.target === e.currentTarget) {
			handleClose();
		}
	}
</script>

{#if open}
	<div
		class="fixed inset-0 flex items-center justify-center p-4 {tutorialMode
			? 'z-200 bg-transparent'
			: 'z-50 bg-black/50'}"
		onclick={handleBackdropClick}
		onkeydown={(e) => !tutorialMode && e.key === 'Escape' && handleClose()}
		role="dialog"
		tabindex="-1"
	>
		<div
			class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border-4 border-black bg-white p-6 {tutorialMode
				? 'z-250'
				: ''}"
			data-tutorial="create-project-modal"
		>
			<div class="mb-6 flex items-center justify-between">
				<h2 class="text-2xl font-bold">{$t.createProject.newProject}</h2>
				{#if !tutorialMode}
					<button
						onclick={handleClose}
						class="cursor-pointer rounded-lg p-1 transition-colors hover:bg-gray-100"
					>
						<X size={24} />
					</button>
				{/if}
			</div>

			{#if error}
				<div class="mb-4 rounded-lg border-2 border-red-500 bg-red-100 p-3 text-sm text-red-700">
					{error}
				</div>
			{/if}

			<div class="space-y-4">
				<!-- Image Upload -->
				<div>
					<label class="mb-1 block text-sm font-bold"
						>{$t.createProject.image}
						<span class="text-gray-400">({$t.createProject.optional})</span></label
					>
					{#if imagePreview}
						<div class="relative h-40 w-full overflow-hidden rounded-lg border-2 border-black">
							<img
								src={imagePreview}
								alt="Preview"
								class="h-full w-full bg-gray-100 object-contain"
							/>
							{#if uploadingImage}
								<div class="absolute inset-0 flex items-center justify-center bg-black/50">
									<span class="font-bold text-white">{$t.createProject.uploading}</span>
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
							class="flex h-32 w-full cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed border-black transition-colors hover:bg-gray-50"
						>
							<Upload size={32} class="mb-2 text-gray-400" />
							<span class="text-sm text-gray-500">{$t.createProject.clickToUploadImage}</span>
							<input type="file" accept="image/*" onchange={handleImageUpload} class="hidden" />
						</label>
					{/if}
				</div>

				<!-- Name -->
				<div>
					<label for="name" class="mb-1 block text-sm font-bold"
						>{$t.createProject.name} <span class="text-red-500">*</span></label
					>
					<input
						id="name"
						type="text"
						bind:value={name}
						maxlength={NAME_MAX}
						required
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
					<p class="mt-1 text-right text-xs text-gray-500">{name.length}/{NAME_MAX}</p>
				</div>

				<!-- Description -->
				<div>
					<label for="description" class="mb-1 block text-sm font-bold"
						>{$t.createProject.description} <span class="text-red-500">*</span></label
					>
					<textarea
						id="description"
						bind:value={description}
						rows="3"
						maxlength={DESC_MAX}
						required
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
					<p
						class="mt-1 text-right text-xs {description.length < DESC_MIN
							? 'text-red-500'
							: 'text-gray-500'}"
					>
						{description.length}/{DESC_MAX} (min {DESC_MIN})
					</p>
				</div>

				<!-- Hackatime Project Dropdown -->
				<div>
					<label class="mb-1 block text-sm font-bold"
						>{$t.createProject.hackatimeProject}
						<span class="text-gray-400">({$t.createProject.optional})</span></label
					>
					{#if selectedHackatimeProjects.length > 0}
						<div class="mb-2 flex flex-wrap gap-2">
							{#each selectedHackatimeProjects as hp}
								<span
									class="flex items-center gap-1 rounded-full border-2 border-black bg-gray-100 px-3 py-1 text-sm font-medium"
								>
									{hp.name}
									<span class="text-gray-500">({formatHours(hp.hours)}h)</span>
									<button
										type="button"
										onclick={() => removeSelectedProject(hp.name)}
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
							class="flex w-full items-center justify-between rounded-lg border-2 border-black px-4 py-2 text-left focus:border-dashed focus:outline-none"
						>
							{#if loadingProjects}
								<span class="text-gray-500">{$t.createProject.loadingProjects}</span>
							{:else if selectedHackatimeProjects.length > 0}
								<span class="text-gray-500">add another project...</span>
							{:else}
								<span class="text-gray-500">{$t.createProject.selectAProject}</span>
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
									<div class="px-4 py-2 text-sm text-gray-500">
										{$t.createProject.noProjectsFound}
									</div>
								{:else}
									{#each hackatimeProjects as project}
										{@const isSelected = selectedHackatimeProjects.some(
											(p) => p.name === project.name
										)}
										<button
											type="button"
											onclick={() => selectProject(project)}
											class="flex w-full cursor-pointer items-center justify-between px-4 py-2 text-left hover:bg-gray-100 {isSelected
												? 'bg-gray-50'
												: ''}"
										>
											<span class="flex items-center gap-2">
												{#if isSelected}
													<Check size={16} class="text-green-600" />
												{/if}
												<span class="font-medium">{project.name}</span>
											</span>
											<span class="text-sm text-gray-500">{formatHours(project.hours)}h</span>
										</button>
									{/each}
								{/if}
							</div>
						{/if}
					</div>
				</div>

				<!-- GitHub URL (optional) -->
				<div>
					<label for="githubUrl" class="mb-1 block text-sm font-bold"
						>{$t.createProject.githubUrl}
						<span class="text-gray-400">({$t.createProject.optional})</span></label
					>
					<input
						id="githubUrl"
						type="url"
						bind:value={githubUrl}
						placeholder="https://github.com/user/repo"
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
				</div>

				<!-- Tier Selector -->
				<div>
					<label class="mb-1 block text-sm font-bold">{$t.createProject.projectTier}</label>
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
								<span>{$t.dashboard.tier} {tier.value}</span>
								<p
									class="mt-1 text-xs {selectedTier === tier.value
										? 'text-gray-300'
										: 'text-gray-500'}"
								>
									{tier.description}
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
						<span class="text-sm font-bold">{$t.createProject.isUpdateLabel}</span>
					</label>
				</div>

				{#if isUpdate}
					<div>
						<label for="updateDescription" class="mb-1 block text-sm font-bold"
							>{$t.createProject.whatDidYouUpdate} <span class="text-red-500">*</span></label
						>
						<textarea
							id="updateDescription"
							bind:value={updateDescription}
							rows="3"
							placeholder={$t.createProject.updateDescriptionPlaceholder}
							class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						></textarea>
						{#if updateDescription.trim().length === 0}
							<p class="mt-1 text-xs text-red-500">{$t.createProject.pleaseDescribeUpdate}</p>
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
						<span class="text-sm font-bold">{$t.createProject.usedAiLabel}</span>
					</label>
				</div>

				{#if usedAi}
					<div>
						<label for="aiDescription" class="mb-1 block text-sm font-bold"
							>{$t.createProject.howWasAiUsed} <span class="text-red-500">*</span></label
						>
						<textarea
							id="aiDescription"
							bind:value={aiDescription}
							rows="3"
							placeholder={$t.createProject.aiDescriptionPlaceholder}
							class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
						></textarea>
						{#if aiDescription.trim().length === 0}
							<p class="mt-1 text-xs text-red-500">{$t.createProject.pleaseDescribeAiUsage}</p>
						{/if}
					</div>
				{/if}

				<!-- Requirements Checklist -->
				<div class="rounded-lg border-2 border-black p-4">
					<p class="mb-3 font-bold">{$t.createProject.requirements}</p>
					<ul class="space-y-2">
						<li class="flex items-center gap-2 text-sm">
							<span
								class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasName
									? 'bg-black text-white'
									: ''}"
							>
								{#if hasName}<Check size={12} />{/if}
							</span>
							<span class={hasName ? '' : 'text-gray-500'}>{$t.createProject.addProjectName}</span>
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
								>{$t.createProject.writeDescription.replace('{min}', String(DESC_MIN))}</span
							>
						</li>
					</ul>
				</div>
			</div>

			<div class="mt-6 flex gap-3">
				<button
					onclick={handleClose}
					disabled={loading || tutorialMode}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={handleSubmit}
					disabled={loading || !allRequirementsMet}
					class="flex-1 cursor-pointer rounded-full bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
				>
					{loading ? $t.common.creating : $t.common.create}
				</button>
			</div>
		</div>
	</div>
{/if}
