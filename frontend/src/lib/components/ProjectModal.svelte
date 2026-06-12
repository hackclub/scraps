<script lang="ts">
	import { X, ChevronDown, Upload, Check } from '@lucide/svelte';
	import { API_URL } from '$lib/config';
	import { formatHours, parseHackatimeProjectName } from '$lib/utils';

	interface Project {
		id: number;
		userId: string;
		name: string;
		description: string;
		image: string | null;
		githubUrl: string | null;
		hackatimeProject: string | null;
		hours: number;
		status: string;
	}

	interface HackatimeProject {
		name: string;
		hours: number;
		repoUrl: string | null;
		languages: string[];
	}

	let {
		project = $bindable<Project | null>(null),
		onClose,
		onSave
	}: {
		project: Project | null;
		onClose: () => void;
		onSave: (project: Project) => void;
	} = $props();

	let editedProject = $state<Project | null>(null);
	let imagePreview = $state<string | null>(null);
	let uploadingImage = $state(false);
	let hackatimeProjects = $state<HackatimeProject[]>([]);
	let _userSlackId = $state<string | null>(null);
	let selectedHackatimeName = $state<string | null>(null);
	let loadingProjects = $state(false);
	let showDropdown = $state(false);
	let loading = $state(false);
	let error = $state<string | null>(null);

	const NAME_MAX = 50;
	const DESC_MIN = 20;
	const DESC_MAX = 1000;

	let hasImage = $derived(!!editedProject?.image);
	let hasHackatime = $derived(!!selectedHackatimeName);
	let hasGithub = $derived(!!editedProject?.githubUrl?.trim());
	let hasDescription = $derived(
		(editedProject?.description?.trim().length ?? 0) >= DESC_MIN &&
			(editedProject?.description?.trim().length ?? 0) <= DESC_MAX
	);
	let hasName = $derived(
		(editedProject?.name?.trim().length ?? 0) > 0 &&
			(editedProject?.name?.trim().length ?? 0) <= NAME_MAX
	);
	let allRequirementsMet = $derived(
		hasImage && hasHackatime && hasGithub && hasDescription && hasName
	);

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
		if (project) {
			editedProject = { ...project };
			imagePreview = project.image;
			error = null;
			selectedHackatimeName = project.hackatimeProject
				? parseHackatimeProjectName(project.hackatimeProject)
				: null;
			fetchHackatimeProjects();
		}
	});

	async function handleImageUpload(event: Event) {
		const input = event.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file || !editedProject) return;

		if (file.size > 5 * 1024 * 1024) {
			error = 'Image must be less than 5MB';
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

			if (editedProject) {
				editedProject.image = data.url;
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to upload image';
			imagePreview = editedProject?.image || null;
		} finally {
			uploadingImage = false;
		}
	}

	function removeImage() {
		if (editedProject) {
			editedProject.image = null;
		}
		imagePreview = null;
	}

	function selectHackatimeProject(hp: HackatimeProject) {
		if (editedProject) {
			selectedHackatimeName = hp.name;
			editedProject.hours = hp.hours;
			if (hp.repoUrl && !editedProject.githubUrl) {
				editedProject.githubUrl = hp.repoUrl;
			}
		}
		showDropdown = false;
	}

	async function handleSave() {
		if (!editedProject || !allRequirementsMet) return;

		loading = true;
		error = null;

		const hackatimeValue = selectedHackatimeName || null;

		try {
			const response = await fetch(`${API_URL}/projects/${editedProject.id}`, {
				method: 'PUT',
				headers: {
					'Content-Type': 'application/json'
				},
				credentials: 'include',
				body: JSON.stringify({
					name: editedProject.name,
					description: editedProject.description,
					image: editedProject.image,
					githubUrl: editedProject.githubUrl,
					hackatimeProject: hackatimeValue || null
				})
			});

			if (!response.ok) {
				const data = await response.json().catch(() => ({}));
				throw new Error(data.message || 'Failed to save project');
			}

			const updatedProject = await response.json();
			onSave(updatedProject);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to save project';
		} finally {
			loading = false;
		}
	}

	function handleBackdropClick(e: MouseEvent) {
		if (e.target === e.currentTarget) {
			onClose();
		}
	}
</script>

{#if project && editedProject}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
		onclick={handleBackdropClick}
		onkeydown={(e) => e.key === 'Escape' && onClose()}
		role="dialog"
		tabindex="-1"
	>
		<div
			class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border-8 border-black bg-white p-6"
		>
			<div class="mb-6 flex items-center justify-between">
				<h2 class="text-2xl font-bold">edit project</h2>
				<button
					onclick={onClose}
					class="cursor-pointer rounded-lg p-1 transition-colors hover:bg-gray-100"
				>
					<X size={24} />
				</button>
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
						>image <span class="text-red-500">*</span></label
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
									<span class="font-bold text-white">uploading...</span>
								</div>
							{:else}
								<button
									type="button"
									onclick={removeImage}
									class="absolute top-2 right-2 rounded-full border-2 border-black bg-white p-1 hover:bg-gray-100"
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
							<span class="text-sm text-gray-500">click to upload image</span>
							<input type="file" accept="image/*" onchange={handleImageUpload} class="hidden" />
						</label>
					{/if}
				</div>

				<div>
					<label for="name" class="mb-1 block text-sm font-bold"
						>name <span class="text-red-500">*</span></label
					>
					<input
						id="name"
						type="text"
						bind:value={editedProject.name}
						maxlength={NAME_MAX}
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
					<p class="mt-1 text-right text-xs text-gray-500">
						{editedProject.name.length}/{NAME_MAX}
					</p>
				</div>

				<div>
					<label for="description" class="mb-1 block text-sm font-bold"
						>description <span class="text-red-500">*</span></label
					>
					<textarea
						id="description"
						bind:value={editedProject.description}
						rows="3"
						maxlength={DESC_MAX}
						class="w-full resize-none rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					></textarea>
					<p
						class="mt-1 text-right text-xs {editedProject.description.length < DESC_MIN
							? 'text-red-500'
							: 'text-gray-500'}"
					>
						{editedProject.description.length}/{DESC_MAX} (min {DESC_MIN})
					</p>
				</div>

				<div>
					<label for="githubUrl" class="mb-1 block text-sm font-bold"
						>github url <span class="text-red-500">*</span></label
					>
					<input
						id="githubUrl"
						type="url"
						bind:value={editedProject.githubUrl}
						placeholder="https://github.com/user/repo"
						class="w-full rounded-lg border-2 border-black px-4 py-2 focus:border-dashed focus:outline-none"
					/>
				</div>

				<!-- Hackatime Project Dropdown -->
				<div>
					<label class="mb-1 block text-sm font-bold"
						>hackatime project <span class="text-red-500">*</span></label
					>
					<div class="relative">
						<button
							type="button"
							onclick={() => (showDropdown = !showDropdown)}
							class="flex w-full items-center justify-between rounded-lg border-2 border-black px-4 py-2 text-left focus:border-dashed focus:outline-none"
						>
							{#if loadingProjects}
								<span class="text-gray-500">loading projects...</span>
							{:else if selectedHackatimeName}
								<span
									>{selectedHackatimeName}
									<span class="text-gray-500">({formatHours(editedProject.hours)}h)</span></span
								>
							{:else}
								<span class="text-gray-500">select a project</span>
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
									<div class="px-4 py-2 text-sm text-gray-500">no projects found</div>
								{:else}
									{#each hackatimeProjects as hp}
										<button
											type="button"
											onclick={() => selectHackatimeProject(hp)}
											class="flex w-full items-center justify-between px-4 py-2 text-left hover:bg-gray-100"
										>
											<span class="font-medium">{hp.name}</span>
											<span class="text-sm text-gray-500">{formatHours(hp.hours)}h</span>
										</button>
									{/each}
								{/if}
							</div>
						{/if}
					</div>
				</div>
			</div>

			<!-- Requirements Checklist -->
			<div class="mt-6 rounded-lg border-2 border-black bg-gray-50 p-4">
				<p class="mb-3 text-sm font-bold">requirements</p>
				<ul class="space-y-2 text-sm">
					<li class="flex items-center gap-2">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasName
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasName}<Check size={12} />{/if}
						</span>
						<span class={hasName ? '' : 'text-gray-500'}>name (max {NAME_MAX} chars)</span>
					</li>
					<li class="flex items-center gap-2">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasDescription
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasDescription}<Check size={12} />{/if}
						</span>
						<span class={hasDescription ? '' : 'text-gray-500'}
							>description ({DESC_MIN}-{DESC_MAX} chars)</span
						>
					</li>
					<li class="flex items-center gap-2">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasImage
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasImage}<Check size={12} />{/if}
						</span>
						<span class={hasImage ? '' : 'text-gray-500'}>project image</span>
					</li>
					<li class="flex items-center gap-2">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasHackatime
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasHackatime}<Check size={12} />{/if}
						</span>
						<span class={hasHackatime ? '' : 'text-gray-500'}>linked to hackatime project</span>
					</li>
					<li class="flex items-center gap-2">
						<span
							class="flex h-5 w-5 items-center justify-center rounded-full border-2 border-black {hasGithub
								? 'bg-black text-white'
								: ''}"
						>
							{#if hasGithub}<Check size={12} />{/if}
						</span>
						<span class={hasGithub ? '' : 'text-gray-500'}>github repository</span>
					</li>
				</ul>
			</div>

			<div class="mt-6 flex gap-3">
				<button
					onclick={onClose}
					disabled={loading}
					class="flex-1 rounded-full border-2 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
				>
					cancel
				</button>
				{#if allRequirementsMet}
					<button
						onclick={handleSave}
						disabled={loading}
						class="flex-1 rounded-full bg-black px-4 py-2 font-bold text-white transition-all duration-200 hover:bg-gray-800 disabled:opacity-50"
					>
						{loading ? 'saving...' : 'save'}
					</button>
				{/if}
			</div>
		</div>
	</div>
{/if}
