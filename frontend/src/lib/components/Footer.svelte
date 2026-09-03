<script lang="ts">
	import { t } from '$lib/i18n';
	import { deployVersion } from '$lib/config';
</script>

<footer class="w-full py-4 text-center text-sm text-gray-600">
	{$t.footer.madeWith}
	<a href="https://hackclub.com" target="_blank" rel="noopener noreferrer" class="hover:underline"
		>{$t.footer.hackClub}</a
	>{#if $deployVersion}, {$t.footer.commit}
		{#if $deployVersion.url}
			<a
				href={$deployVersion.url}
				target="_blank"
				rel="noopener noreferrer"
				class="font-mono hover:underline">{$deployVersion.short}</a
			>
		{:else}
			<span class="font-mono">{$deployVersion.short}</span>
		{/if}
	{/if}
</footer>
