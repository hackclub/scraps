<script lang="ts">
	import { onMount } from 'svelte';

	onMount(() => {
		const audio = new Audio('/audio/cat.mp3');
		audio.play().catch(() => {});
	});
</script>

<div class="fixed inset-0 z-50 flex flex-col items-center justify-center gap-6 bg-white">
	<h1 class="text-4xl font-bold md:text-5xl">you thought</h1>
	<img src="/images/HA.png" alt="" class="w-64 max-w-[70vw] rounded-2xl" />
</div>
