<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import {
		ArrowLeft,
		Pencil,
		Send,
		Clock,
		CheckCircle,
		XCircle,
		AlertCircle,
		Github,
		AlertTriangle,
		PlaneTakeoff,
		Plus,
		Globe,
		Spool,
		Eye,
		RefreshCw,
		Undo2,
		Bot
	} from '@lucide/svelte';
	import { getUser } from '$lib/auth-client';
	import { API_URL } from '$lib/config';
	import { formatHours } from '$lib/utils';
	import ProjectPlaceholder from '$lib/components/ProjectPlaceholder.svelte';
	import Markdown from '$lib/components/Markdown.svelte';
	import { tutorialActiveStore } from '$lib/stores';
	import { t } from '$lib/i18n';

	let { data } = $props();

	interface Project {
		id: number;
		name: string;
		description: string;
		image: string | null;
		githubUrl: string | null;
		playableUrl: string | null;
		hackatimeProject?: string | null;
		hours: number;
		hoursOverride?: number | null;
		tier: number;
		status: string;
		scrapsAwarded: number;
		views: number;
		updateDescription: string | null;
		usedAi: boolean;
		effectiveHours: number;
		deductedHours: number;
		createdAt: string;
		updatedAt: string;
	}

	interface Owner {
		id: number;
		username: string | null;
		avatar: string | null;
	}

	interface ActivityEntry {
		type: 'review' | 'created' | 'submitted' | 'unsubmitted' | 'scraps_earned';
		action?: string;
		feedbackForAuthor?: string | null;
		createdAt: string;
		reviewer?: {
			id: number;
			username: string | null;
			avatar: string | null;
		} | null;
	}

	let project = $state<Project | null>(null);
	let owner = $state<Owner | null>(null);
	let isOwner = $state(false);
	let isAdmin = $state(false);
	let activity = $state<ActivityEntry[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let syncingHours = $state(false);
	let showUnsubmitConfirm = $state(false);
	let unsubmitting = $state(false);

	onMount(async () => {
		const user = await getUser();
		if (!user) {
			goto('/');
			return;
		}
		isAdmin = user.role === 'admin' || user.role === 'creator';

		try {
			const projectRes = await fetch(`${API_URL}/projects/${data.id}`, { credentials: 'include' });

			if (!projectRes.ok) {
				throw new Error('Project not found');
			}

			const result = await projectRes.json();
			if (result.error) {
				throw new Error(result.error);
			}

			project = result.project;
			owner = result.owner;
			isOwner = result.isOwner;
			activity = result.activity || [];
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load project';
		} finally {
			loading = false;
		}
	});

	function getReviewIcon(action: string) {
		switch (action) {
			case 'approved':
				return CheckCircle;
			case 'denied':
				return AlertCircle;
			case 'permanently_rejected':
			case 'scraps_unawarded':
				return XCircle;
			default:
				return Clock;
		}
	}

	function getReviewColor(action: string) {
		switch (action) {
			case 'approved':
				return 'text-green-600';
			case 'denied':
				return 'text-yellow-600';
			case 'permanently_rejected':
				return 'text-red-600';
			case 'scraps_unawarded':
				return 'text-red-600';
			default:
				return 'text-gray-600';
		}
	}

	function getReviewLabel(action: string) {
		switch (action) {
			case 'approved':
				return $t.project.approved;
			case 'denied':
				return $t.project.changesRequested;
			case 'permanently_rejected':
				return $t.project.permanentlyRejected;
			case 'scraps_unawarded':
				return 'scraps unawarded';
			default:
				return action;
		}
	}

	function formatDate(dateString: string) {
		return new Date(dateString).toLocaleDateString('en-US', {
			year: 'numeric',
			month: 'short',
			day: 'numeric',
			hour: '2-digit',
			minute: '2-digit'
		});
	}

	async function syncHours() {
		if (!project || syncingHours) return;
		syncingHours = true;
		try {
			const response = await fetch(`${API_URL}/admin/projects/${project.id}/sync-hours`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await response.json();
			if (data.error) {
				error = data.error;
			} else if (data.updated && project) {
				project.hours = data.hours;
			}
		} catch (e) {
			console.error('Failed to sync hours:', e);
		} finally {
			syncingHours = false;
		}
	}

	async function handleUnsubmit() {
		if (!project || unsubmitting) return;
		unsubmitting = true;
		try {
			const response = await fetch(`${API_URL}/projects/${project.id}/unsubmit`, {
				method: 'POST',
				credentials: 'include'
			});
			const data = await response.json();
			if (data.error) {
				error = data.error;
			} else {
				project.status = 'in_progress';
				showUnsubmitConfirm = false;
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to unsubmit project';
		} finally {
			unsubmitting = false;
		}
	}
</script>

<svelte:head>
	<title>{project?.name || 'project'} - scraps</title>
</svelte:head>

<div class="mx-auto max-w-4xl px-6 pt-24 pb-24 md:px-12">
	{#if isOwner}
		<a
			href="/dashboard"
			class="mb-8 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
		>
			<ArrowLeft size={20} />
			{$t.project.backToDashboard}
		</a>
	{:else if owner}
		<a
			href="/users/{owner.id}"
			class="mb-8 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
		>
			<ArrowLeft size={20} />
			{$t.project.backToProfile.replace('{username}', owner.username || '')}
		</a>
	{:else}
		<a
			href="/leaderboard"
			class="mb-8 inline-flex cursor-pointer items-center gap-2 font-bold hover:underline"
		>
			<ArrowLeft size={20} />
			{$t.project.back}
		</a>
	{/if}

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
		<!-- Project Header -->
		<div class="mb-8 overflow-hidden rounded-2xl border-4 border-black bg-white">
			<!-- Image -->
			<div class="h-64 w-full overflow-hidden border-b-4 border-black">
				{#if project.image}
					<img src={project.image} alt={project.name} class="h-full w-full object-cover" />
				{:else}
					<ProjectPlaceholder seed={project.id} />
				{/if}
			</div>

			<!-- Content -->
			<div class="p-6">
				<div class="mb-2 flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
					<h1 class="min-w-0 text-3xl font-bold wrap-break-word md:text-4xl">{project.name}</h1>
					{#if project.status === 'shipped'}
						<span
							class="flex shrink-0 items-center gap-1 rounded-full border-2 border-green-600 bg-green-100 px-3 py-1 text-sm font-bold text-green-700"
						>
							<CheckCircle size={14} />
							{$t.project.shipped}
						</span>
					{:else if project.status === 'waiting_for_review'}
						<span
							class="flex shrink-0 items-center gap-1 rounded-full border-2 border-yellow-600 bg-yellow-100 px-3 py-1 text-sm font-bold text-yellow-700"
						>
							<Clock size={14} />
							{$t.project.awaitingReview}
						</span>
					{:else}
						<span
							class="flex shrink-0 items-center gap-1 rounded-full border-2 border-yellow-600 bg-yellow-100 px-3 py-1 text-sm font-bold text-yellow-700"
						>
							<AlertTriangle size={14} />
							{$t.project.inProgress}
						</span>
					{/if}
				</div>
				<div class="mb-4 flex flex-wrap items-center gap-2">
					<span
						class="rounded-full border-2 border-gray-400 bg-gray-100 px-3 py-1 text-sm font-bold text-gray-700"
					>
						{$t.project.tier.replace('{value}', String(project.tier))}
					</span>
					{#if project.usedAi}
						<span
							class="flex items-center gap-1 rounded-full border-2 border-purple-400 bg-purple-100 px-3 py-1 text-sm font-bold text-purple-700"
						>
							<Bot size={14} />
							{$t.project.aiWasUsed}
						</span>
					{/if}
				</div>

				{#if project.description}
					<Markdown content={project.description} class="mb-4 text-lg text-gray-700" />
				{:else}
					<p class="mb-4 text-lg text-gray-400 italic">{$t.project.noDescriptionYet}</p>
				{/if}

				{#if project.updateDescription}
					<div class="mb-4 rounded-lg border-2 border-dashed border-gray-400 bg-gray-50 p-4">
						<p class="mb-1 flex items-center gap-1.5 text-sm font-bold text-gray-600">
							<RefreshCw size={14} />
							{$t.project.whatWasUpdated}
						</p>
						<p class="text-gray-700">{project.updateDescription}</p>
					</div>
				{/if}

				<div class="mb-3 flex flex-wrap items-center gap-3">
					<span
						class="flex items-center gap-2 rounded-full border-4 border-black bg-white px-4 py-2 font-bold"
					>
						<Eye size={18} />
						{$t.project.views.replace('{count}', project.views.toLocaleString())}
					</span>
					{#if project.scrapsAwarded > 0}
						<span
							class="flex items-center gap-2 rounded-full border-4 border-green-600 bg-green-100 px-4 py-2 font-bold text-green-700"
						>
							<Spool size={18} />
							{$t.project.scrapsEarned.replace('{count}', String(project.scrapsAwarded))}
						</span>
					{/if}
				</div>
				<div class="flex flex-wrap items-center gap-3">
					<span
						class="flex items-center gap-2 rounded-full border-4 border-black bg-white px-4 py-2 font-bold"
					>
						<Clock size={18} />
						{#if (isOwner || isAdmin) && project.deductedHours > 0}
							<span class="text-gray-400 line-through">{formatHours(project.hours)}h</span>
						{:else}
							{formatHours(project.effectiveHours)}h
						{/if}
					</span>
					{#if (isOwner || isAdmin) && project.deductedHours > 0}
						<span
							class="flex items-center gap-2 rounded-full border-4 border-yellow-500 bg-yellow-100 px-4 py-2 font-bold text-yellow-700"
							title="{formatHours(
								project.deductedHours
							)}h deducted from overlapping shipped projects"
						>
							{formatHours(project.effectiveHours)}h effective
						</span>
					{/if}
					{#if project.githubUrl}
						<a
							href={project.githubUrl}
							target="_blank"
							rel="noopener noreferrer"
							class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
						>
							<Github size={18} />
							{$t.project.viewOnGithub}
						</a>
					{:else}
						<span
							class="flex cursor-not-allowed items-center gap-2 rounded-full border-4 border-dashed border-gray-300 px-4 py-2 font-bold text-gray-400"
						>
							<Github size={18} />
							{$t.project.viewOnGithub}
						</span>
					{/if}
					{#if project.playableUrl}
						<a
							href={project.playableUrl}
							target="_blank"
							rel="noopener noreferrer"
							class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-solid border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed"
						>
							<Globe size={18} />
							{$t.project.tryItOut}
						</a>
					{:else}
						<span
							class="flex cursor-not-allowed items-center gap-2 rounded-full border-4 border-dashed border-gray-300 px-4 py-2 font-bold text-gray-400"
						>
							<Globe size={18} />
							{$t.project.tryItOut}
						</span>
					{/if}
					{#if isAdmin}
						<button
							onclick={syncHours}
							disabled={syncingHours}
							title="Sync hours from Hackatime"
							class="flex cursor-pointer items-center gap-2 rounded-full border-4 border-black px-4 py-2 font-bold transition-all duration-200 hover:border-dashed disabled:cursor-not-allowed disabled:opacity-50"
						>
							<RefreshCw size={18} class={syncingHours ? 'animate-spin' : ''} />
							{syncingHours ? 'syncing...' : 'sync hours'}
						</button>
					{/if}
				</div>
			</div>
		</div>

		<!-- Owner Info (for non-owners) -->
		{#if !isOwner && owner}
			<div class="mb-8 rounded-2xl border-4 border-black p-6">
				<h2 class="mb-4 text-xl font-bold">{$t.project.createdBy}</h2>
				<a
					href="/users/{owner.id}"
					class="flex cursor-pointer items-center gap-4 transition-all duration-200 hover:opacity-80"
				>
					{#if owner.avatar}
						<img src={owner.avatar} alt="" class="h-12 w-12 rounded-full border-2 border-black" />
					{:else}
						<div class="h-12 w-12 rounded-full border-2 border-black bg-gray-200"></div>
					{/if}
					<span class="text-lg font-bold">{owner.username || $t.project.unknown}</span>
				</a>
			</div>
		{/if}

		<!-- Action Buttons (only for owner) -->
		{#if isOwner}
			<div class="mb-8 flex flex-col gap-3">
				<div class="flex flex-col gap-3 sm:flex-row sm:gap-4">
					{#if project.status === 'waiting_for_review'}
						<span
							class="flex flex-1 items-center justify-center gap-2 rounded-full border-4 border-black bg-gray-200 px-4 py-3 text-center text-sm font-bold text-gray-600 sm:px-6 sm:text-base"
						>
							<Pencil size={18} />
							{$t.project.editProject}
						</span>
					{:else}
						<a
							href="/projects/{project.id}/edit"
							class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black px-4 py-3 text-center text-sm font-bold transition-all duration-200 hover:border-dashed sm:px-6 sm:text-base"
						>
							<Pencil size={18} />
							{$t.project.editProject}
						</a>
					{/if}
					{#if project.status === 'waiting_for_review'}
						<span
							class="flex flex-1 items-center justify-center gap-2 rounded-full border-4 border-black bg-gray-200 px-4 py-3 text-center text-sm font-bold text-gray-600 sm:px-6 sm:text-base"
						>
							<Send size={18} />
							{$t.project.awaitingReview}
						</span>
					{:else if project.status === 'shipped'}
						<a
							href="/projects/{project.id}/submit"
							class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-3 text-sm font-bold text-white transition-all duration-200 hover:bg-gray-800 sm:px-6 sm:text-base"
						>
							<RefreshCw size={18} />
							ship update
						</a>
					{:else if project.status === 'permanently_rejected'}
						<span
							class="flex flex-1 cursor-not-allowed items-center justify-center gap-2 rounded-full border-4 border-black bg-red-100 px-4 py-3 text-center text-sm font-bold text-red-600 sm:px-6 sm:text-base"
						>
							<XCircle size={18} />
							{$t.project.permanentlyRejected}
						</span>
					{:else if $tutorialActiveStore}
						<span
							data-tutorial="submit-button"
							class="flex flex-1 cursor-not-allowed items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-3 text-sm font-bold text-white sm:px-6 sm:text-base"
						>
							<Send size={18} />
							{$t.project.reviewAndSubmit}
						</span>
					{:else}
						<a
							href="/projects/{project.id}/submit"
							data-tutorial="submit-button"
							class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-black bg-black px-4 py-3 text-sm font-bold text-white transition-all duration-200 hover:bg-gray-800 sm:px-6 sm:text-base"
						>
							<Send size={18} />
							{$t.project.reviewAndSubmit}
						</a>
					{/if}
				</div>
				{#if project.status === 'waiting_for_review'}
					<button
						onclick={() => (showUnsubmitConfirm = true)}
						class="flex w-full cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-red-500 bg-red-100 px-4 py-3 text-sm font-bold text-red-600 transition-all duration-200 hover:border-dashed hover:bg-red-200 sm:px-6 sm:text-base"
					>
						<Undo2 size={18} />
						{$t.project.unsubmitProject}
					</button>
				{/if}
			</div>

			{#if error}
				<div class="mb-8 rounded-lg border-2 border-red-500 bg-red-100 p-4 text-red-700">
					{error}
				</div>
			{/if}
		{/if}

		<!-- Activity Timeline -->
		<div>
			<h2 class="mb-6 text-2xl font-bold">{$t.project.activity}</h2>

			{#if activity.length === 0}
				<div class="rounded-2xl border-4 border-dashed border-gray-300 p-8 text-center">
					<p class="text-gray-500">{$t.project.noActivityYet}</p>
					{#if isOwner}
						<p class="mt-2 text-sm text-gray-400">{$t.project.submitToGetStarted}</p>
					{/if}
				</div>
			{:else}
				<div class="relative">
					<!-- Timeline line -->
					<div class="absolute top-0 bottom-0 left-3 w-0.5 bg-gray-200"></div>
					<div class="space-y-4">
						{#each activity as entry, _i}
							{#if entry.type === 'review' && entry.action}
								{@const ReviewIcon = getReviewIcon(entry.action)}
								<div class="relative">
									<div
										class="ml-8 rounded-2xl border-4 border-black bg-white p-6 transition-all duration-200 hover:border-dashed"
									>
										<div
											class="absolute top-6 left-0 z-10 flex h-6 w-6 items-center justify-center rounded-full bg-white"
										>
											<ReviewIcon size={20} class={getReviewColor(entry.action)} />
										</div>
										<div>
											<div class="mb-2 flex items-center justify-between">
												<span class="font-bold">{getReviewLabel(entry.action)}</span>
												<span class="text-sm text-gray-500">{formatDate(entry.createdAt)}</span>
											</div>
											{#if entry.feedbackForAuthor}
												<p class="mb-3 text-gray-700">{entry.feedbackForAuthor}</p>
											{/if}
											{#if entry.reviewer}
												<a
													href="/users/{entry.reviewer.id}"
													class="inline-flex cursor-pointer items-center gap-2 text-sm text-gray-500 transition-all duration-200 hover:text-black"
												>
													{#if entry.reviewer.avatar}
														<img
															src={entry.reviewer.avatar}
															alt=""
															class="h-6 w-6 rounded-full border-2 border-black"
														/>
													{:else}
														<div
															class="h-6 w-6 rounded-full border-2 border-black bg-gray-200"
														></div>
													{/if}
													<span
														>{$t.project.reviewedBy}
														<strong>{entry.reviewer.username || $t.project.reviewer}</strong></span
													>
												</a>
											{/if}
										</div>
									</div>
								</div>
							{:else if entry.type === 'scraps_earned'}
								<div class="relative ml-8 flex items-center gap-3 py-2">
									<div
										class="absolute left-[-26px] z-10 flex h-6 w-6 items-center justify-center rounded-full bg-white"
									>
										<Spool size={16} class="text-green-600" />
									</div>
									<span class="text-sm font-bold text-green-600"
										>{entry.action} · {formatDate(entry.createdAt)}</span
									>
								</div>
							{:else if entry.type === 'submitted'}
								<div class="relative ml-8 flex items-center gap-3 py-2">
									<div
										class="absolute left-[-26px] z-10 flex h-6 w-6 items-center justify-center rounded-full bg-white"
									>
										<PlaneTakeoff size={16} class="text-gray-500" />
									</div>
									<span class="text-sm text-gray-500"
										>{$t.project.submittedForReview} · {formatDate(entry.createdAt)}</span
									>
								</div>
							{:else if entry.type === 'unsubmitted'}
								<div class="relative ml-8 flex items-center gap-3 py-2">
									<div
										class="absolute left-[-26px] z-10 flex h-6 w-6 items-center justify-center rounded-full bg-white"
									>
										<Undo2 size={16} class="text-orange-500" />
									</div>
									<span class="text-sm text-orange-500"
										>{$t.project.unsubmittedFromReview} · {formatDate(entry.createdAt)}</span
									>
								</div>
							{:else if entry.type === 'created'}
								<div class="relative ml-8 flex items-center gap-3 py-2">
									<div
										class="absolute left-[-26px] z-10 flex h-6 w-6 items-center justify-center rounded-full bg-white"
									>
										<Plus size={16} class="text-gray-500" />
									</div>
									<span class="text-sm text-gray-500"
										>{$t.project.projectCreated} · {formatDate(entry.createdAt)}</span
									>
								</div>
							{/if}
						{/each}
					</div>
				</div>
			{/if}
		</div>
	{/if}
</div>

<!-- Unsubmit Confirmation Modal -->
{#if showUnsubmitConfirm && project}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-6"
		onclick={(e) => e.target === e.currentTarget && (showUnsubmitConfirm = false)}
		onkeydown={(e) => e.key === 'Escape' && (showUnsubmitConfirm = false)}
		role="dialog"
		tabindex="-1"
	>
		<div class="w-full max-w-lg rounded-2xl border-4 border-black bg-white p-6">
			<h2 class="mb-4 text-2xl font-bold">{$t.project.unsubmitConfirmTitle}</h2>
			<p class="mb-6 text-gray-700">
				{$t.project.unsubmitConfirmMessage}
			</p>
			<div class="flex gap-4">
				<button
					onclick={() => (showUnsubmitConfirm = false)}
					disabled={unsubmitting}
					class="flex-1 cursor-pointer rounded-full border-4 border-black px-4 py-3 font-bold transition-all duration-200 hover:border-dashed disabled:opacity-50"
				>
					{$t.common.cancel}
				</button>
				<button
					onclick={handleUnsubmit}
					disabled={unsubmitting}
					class="flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-full border-4 border-red-600 bg-red-600 px-4 py-3 font-bold text-white transition-all duration-200 hover:bg-red-700 disabled:opacity-50"
				>
					<Undo2 size={18} />
					{unsubmitting ? $t.project.unsubmitting : $t.project.unsubmitProject}
				</button>
			</div>
		</div>
	</div>
{/if}
