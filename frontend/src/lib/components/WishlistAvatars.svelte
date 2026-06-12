<script lang="ts">
	import { Heart } from '@lucide/svelte';

	interface WishlistUser {
		id: number;
		name: string;
		avatar: string;
	}

	let {
		users = [],
		onWishlist
	}: {
		users: WishlistUser[];
		onWishlist: () => void;
	} = $props();

	let expanded = $state(false);
	let containerRef = $state<HTMLDivElement | null>(null);

	function toggleExpand() {
		expanded = !expanded;
	}

	function handleClickOutside(e: MouseEvent) {
		if (containerRef && !containerRef.contains(e.target as Node)) {
			expanded = false;
		}
	}

	$effect(() => {
		if (expanded) {
			document.addEventListener('click', handleClickOutside);
			return () => document.removeEventListener('click', handleClickOutside);
		}
	});

	const maxVisible = 3;
	const visibleUsers = $derived(users.slice(0, maxVisible));
	const remainingCount = $derived(Math.max(0, users.length - maxVisible));
</script>

<div class="relative" bind:this={containerRef}>
	<div class="flex items-center gap-2">
		<!-- Wishlist button -->
		<button
			onclick={onWishlist}
			class="cursor-pointer rounded-full border-2 border-black p-2 transition-colors hover:bg-gray-100"
			title="Add to wishlist"
		>
			<Heart size={16} />
		</button>

		<!-- Stacked avatars -->
		{#if users.length > 0}
			<button onclick={toggleExpand} class="flex cursor-pointer items-center -space-x-2">
				{#each visibleUsers as user, i}
					<img
						src={user.avatar}
						alt={user.name}
						class="h-8 w-8 rounded-full border-2 border-white object-cover transition-transform hover:scale-110"
						style="z-index: {maxVisible - i}"
					/>
				{/each}
				{#if remainingCount > 0}
					<div
						class="flex h-8 w-8 items-center justify-center rounded-full border-2 border-white bg-black text-xs font-bold text-white"
						style="z-index: 0"
					>
						+{remainingCount}
					</div>
				{/if}
			</button>
		{/if}
	</div>

	<!-- Expanded quarter circle menu -->
	{#if expanded && users.length > 0}
		<div class="absolute right-0 bottom-full mb-2 origin-bottom-right">
			<div class="relative h-48 w-48 overflow-hidden">
				<div
					class="absolute right-0 bottom-0 h-96 w-96 overflow-hidden rounded-full border-4 border-black bg-white"
					style="transform: translate(50%, 50%)"
				>
					<div class="scrollbar-hide absolute top-0 left-0 h-48 w-48 overflow-y-auto p-4">
						<div class="space-y-2">
							{#each users as user (user.id)}
								<div
									class="flex items-center gap-2 rounded-lg p-2 transition-colors hover:bg-gray-100"
								>
									<img
										src={user.avatar}
										alt={user.name}
										class="h-10 w-10 rounded-full border-2 border-black object-cover"
									/>
									<span class="truncate text-sm font-bold">{user.name}</span>
								</div>
							{/each}
						</div>
					</div>
				</div>
			</div>
		</div>
	{/if}
</div>

<style>
	.scrollbar-hide {
		-ms-overflow-style: none;
		scrollbar-width: none;
	}
	.scrollbar-hide::-webkit-scrollbar {
		display: none;
	}
</style>
