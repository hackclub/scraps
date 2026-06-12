<script lang="ts">
	const phrases = [
		'fantasy football',
		'scrap that, ship this',
		'turning leftovers into legendary',
		'one persons scraps, anothers treasure',
		'built different, shipped anyway',
		'ctrl+z your regrets',
		'powered by fudge and caffeine',
		'404 boredom not found',
		'shipping since 2025'
	];

	const randomPhrase = phrases[Math.floor(Math.random() * phrases.length)];
</script>

<span>{randomPhrase}</span>
