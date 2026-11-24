<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { getUser, requireLogin } from '$lib/auth-client';

	const addr = {
		name: 'Sam Example',
		address1: '12 Maple St',
		address2: 'Apt 4',
		city: 'Springfield',
		state: 'IL',
		postalCode: '62704',
		country: 'US'
	};
	const conflicts = [
		{
			id: 9001,
			itemName: 'Stickers',
			when: 'bought Sep 3, 2026',
			isFulfilled: true,
			address: '88 Oak Ave, Shelbyville, IL, 62565, US'
		},
		{
			id: 9002,
			itemName: 'Onboard Posters',
			when: 'won Nov 10, 2026',
			isFulfilled: false,
			address: '12 Maple St, Apt. 4, Springfield, IL, 62704, US'
		}
	];

	let allowed = $state(false);

	onMount(async () => {
		const u = await getUser();
		if (!u) {
			requireLogin();
			return;
		}
		if (u.role !== 'admin') {
			goto('/dashboard');
			return;
		}
		allowed = true;
	});
</script>

<svelte:head>
	<title>order (demo) - scraps</title>
</svelte:head>

{#if allowed}
	<div class="mx-auto max-w-3xl px-6 pt-24 pb-24 md:px-12 md:pt-32">
		<p class="mb-4 text-xs text-gray-400">demo · order data is fake</p>
		<div
			class="rounded-3xl border-4 border-black bg-white p-6 text-sm shadow-[8px_8px_0px_0px_rgba(0,0,0,1)]"
		>
			<div class="mb-3 rounded-xl border-2 border-yellow-600 bg-yellow-50 p-3 text-xs text-yellow-800">
				<p class="mb-1 font-bold">
					are you sure this is the right address? you have {conflicts.length}
					other order{conflicts.length === 1 ? '' : 's'} with a different address:
				</p>
				<ul class="flex flex-col gap-0.5">
					{#each conflicts as c (c.id)}
						<li>
							<span class="font-bold">#{c.id}</span>
							{c.itemName} · {c.when}{c.isFulfilled ? ' (fulfilled)' : ''}: {c.address}
						</li>
					{/each}
				</ul>
			</div>
			<div class="rounded-xl border-2 border-gray-300 bg-white p-4">
				<p class="mb-2 text-xs font-bold text-gray-500 uppercase">
					shipping address <span class="text-gray-400 normal-case">(double-click to copy)</span>
				</p>
				<div class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
					<span class="font-bold text-gray-500">name</span><span>{addr.name}</span>
					<span class="font-bold text-gray-500">address 1</span><span>{addr.address1}</span>
					<span class="font-bold text-gray-500">address 2</span><span>{addr.address2}</span>
					<span class="font-bold text-gray-500">city</span><span>{addr.city}</span>
					<span class="font-bold text-gray-500">state</span><span>{addr.state}</span>
					<span class="font-bold text-gray-500">zip</span><span>{addr.postalCode}</span>
					<span class="font-bold text-gray-500">country</span><span>{addr.country}</span>
				</div>
			</div>
		</div>
	</div>
{/if}
