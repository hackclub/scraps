import { API_URL } from '$lib/config';

export interface Emoji {
	name: string;
	imageUrl: string;
}

export const EMOJI_NAME = "[a-z0-9_+'-]";

const known = new Map<string, string | null>();
const pending = new Map<string, Promise<void>>();

export async function searchEmojis(query: string): Promise<Emoji[]> {
	const res = await fetch(`${API_URL}/emojis?q=${encodeURIComponent(query)}`, {
		credentials: 'include'
	});
	if (!res.ok) return [];
	const emojis: Emoji[] = (await res.json()).emojis || [];
	for (const e of emojis) known.set(e.name.toLowerCase(), e.imageUrl);
	return emojis;
}

export async function lookupEmojis(names: string[]): Promise<Record<string, string>> {
	const wanted = [...new Set(names.map((n) => n.toLowerCase()))];
	const missing = wanted.filter((n) => !known.has(n) && !pending.has(n));

	if (missing.length) {
		const request = fetch(
			`${API_URL}/emojis/lookup?names=${encodeURIComponent(missing.join(','))}`,
			{ credentials: 'include' }
		)
			.then((res) => (res.ok ? res.json() : { emojis: {} }))
			.then((data) => {
				const found: Record<string, string> = data.emojis || {};
				for (const n of missing) known.set(n, found[n] ?? null);
			})
			.catch(() => {})
			.finally(() => {
				for (const n of missing) pending.delete(n);
			});
		for (const n of missing) pending.set(n, request);
	}

	await Promise.all(wanted.map((n) => pending.get(n)).filter(Boolean));

	const result: Record<string, string> = {};
	for (const n of wanted) {
		const url = known.get(n);
		if (url) result[n] = url;
	}
	return result;
}

export function installEmojiAutocomplete(): () => void {
	const list = document.createElement('div');
	list.className = 'emoji-autocomplete';
	list.style.display = 'none';
	document.body.appendChild(list);

	let items: Emoji[] = [];
	let active = 0;
	let target: HTMLTextAreaElement | null = null;
	let tokenStart = 0;
	let requestId = 0;

	const isOpen = () => list.style.display !== 'none';

	function hide() {
		list.style.display = 'none';
		items = [];
		target = null;
	}

	function render() {
		if (!target) return;
		list.replaceChildren();
		items.forEach((e, i) => {
			const row = document.createElement('div');
			if (i === active) row.className = 'active';
			const img = document.createElement('img');
			img.src = e.imageUrl;
			img.loading = 'lazy';
			img.alt = '';
			const label = document.createElement('span');
			label.textContent = `:${e.name}:`;
			row.append(img, label);
			row.addEventListener('mousedown', (ev) => {
				ev.preventDefault();
				choose(i);
			});
			list.appendChild(row);
		});
		const rect = target.getBoundingClientRect();
		list.style.left = `${rect.left}px`;
		list.style.top = `${rect.bottom + 4}px`;
		list.style.width = `${Math.max(240, Math.min(rect.width, 360))}px`;
		list.style.display = items.length ? 'block' : 'none';
		(list.children[active] as HTMLElement | undefined)?.scrollIntoView({ block: 'nearest' });
	}

	function choose(i: number) {
		const e = items[i];
		const el = target;
		if (!e || !el) return hide();
		const caret = el.selectionStart ?? el.value.length;
		const insert = `:${e.name}: `;
		el.value = el.value.slice(0, tokenStart) + insert + el.value.slice(caret);
		const pos = tokenStart + insert.length;
		el.setSelectionRange(pos, pos);
		hide();
		el.dispatchEvent(new Event('input', { bubbles: true }));
		el.focus();
	}

	async function onInput(ev: Event) {
		const el = ev.target;
		if (!(el instanceof HTMLTextAreaElement) || el.dataset.noEmoji !== undefined) return;
		if (el.selectionStart !== el.selectionEnd) return hide();

		const before = el.value.slice(0, el.selectionStart ?? 0);
		const match = before.match(new RegExp(`(^|\\s):(${EMOJI_NAME}{2,})$`, 'i'));
		if (!match) return hide();

		const query = match[2];
		const start = before.length - query.length - 1;
		const id = ++requestId;
		try {
			const found = await searchEmojis(query);
			if (id !== requestId) return;
			target = el;
			tokenStart = start;
			items = found;
			active = 0;
			render();
		} catch {
			hide();
		}
	}

	function onKeydown(ev: KeyboardEvent) {
		if (!isOpen() || ev.target !== target) return;
		const handled = () => {
			ev.preventDefault();
			ev.stopImmediatePropagation();
		};
		if (ev.key === 'ArrowDown') {
			handled();
			active = (active + 1) % items.length;
			render();
		} else if (ev.key === 'ArrowUp') {
			handled();
			active = (active - 1 + items.length) % items.length;
			render();
		} else if (ev.key === 'Enter' || ev.key === 'Tab') {
			handled();
			choose(active);
		} else if (ev.key === 'Escape') {
			handled();
			hide();
		}
	}

	function onFocusOut(ev: FocusEvent) {
		if (ev.target === target) hide();
	}

	function onScroll() {
		if (isOpen()) render();
	}

	document.addEventListener('input', onInput, true);
	document.addEventListener('keydown', onKeydown, true);
	document.addEventListener('focusout', onFocusOut, true);
	window.addEventListener('scroll', onScroll, true);
	window.addEventListener('resize', onScroll);

	return () => {
		document.removeEventListener('input', onInput, true);
		document.removeEventListener('keydown', onKeydown, true);
		document.removeEventListener('focusout', onFocusOut, true);
		window.removeEventListener('scroll', onScroll, true);
		window.removeEventListener('resize', onScroll);
		list.remove();
	};
}

export async function renderEmojis(root: HTMLElement) {
	const pattern = new RegExp(`:(${EMOJI_NAME}+):`, 'gi');
	const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
		acceptNode: (node) =>
			node.parentElement?.closest('code, pre') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
	});

	const nodes: Text[] = [];
	const names = new Set<string>();
	while (walker.nextNode()) {
		const node = walker.currentNode as Text;
		const matches = [...node.data.matchAll(pattern)];
		if (!matches.length) continue;
		nodes.push(node);
		for (const m of matches) names.add(m[1]);
	}
	if (!names.size) return;

	const urls = await lookupEmojis([...names]);

	for (const node of nodes) {
		if (!node.isConnected) continue;
		const frag = document.createDocumentFragment();
		let last = 0;
		let changed = false;
		for (const m of node.data.matchAll(pattern)) {
			const url = urls[m[1].toLowerCase()];
			if (!url) continue;
			frag.append(node.data.slice(last, m.index));
			const img = document.createElement('img');
			img.src = url;
			img.alt = m[0];
			img.title = m[0];
			img.className = 'emoji';
			frag.append(img);
			last = m.index! + m[0].length;
			changed = true;
		}
		if (!changed) continue;
		frag.append(node.data.slice(last));
		node.replaceWith(frag);
	}
}
