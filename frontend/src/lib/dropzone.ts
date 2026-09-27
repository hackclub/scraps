const ACTIVE_CLASSES = ['bg-yellow-50', 'border-solid'];

export function dropzone(node: HTMLElement) {
	let depth = 0;

	function input() {
		const el = node.querySelector<HTMLInputElement>('input[type="file"]');
		return el && !el.disabled ? el : null;
	}

	function setActive(active: boolean) {
		for (const c of ACTIVE_CLASSES) node.classList.toggle(c, active);
	}

	function hasFiles(e: DragEvent) {
		return Array.from(e.dataTransfer?.types ?? []).includes('Files');
	}

	function onDragEnter(e: DragEvent) {
		if (!hasFiles(e) || !input()) return;
		e.preventDefault();
		depth++;
		setActive(true);
	}

	function onDragOver(e: DragEvent) {
		if (!hasFiles(e) || !input()) return;
		e.preventDefault();
		if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
	}

	function onDragLeave() {
		depth = Math.max(0, depth - 1);
		if (depth === 0) setActive(false);
	}

	function onDrop(e: DragEvent) {
		const target = input();
		if (!hasFiles(e) || !target) return;
		e.preventDefault();
		depth = 0;
		setActive(false);
		const file = Array.from(e.dataTransfer?.files ?? []).find((f) => f.type.startsWith('image/'));
		if (!file) return;
		const dt = new DataTransfer();
		dt.items.add(file);
		target.files = dt.files;
		target.dispatchEvent(new Event('change', { bubbles: true }));
	}

	node.addEventListener('dragenter', onDragEnter);
	node.addEventListener('dragover', onDragOver);
	node.addEventListener('dragleave', onDragLeave);
	node.addEventListener('drop', onDrop);

	return {
		destroy() {
			node.removeEventListener('dragenter', onDragEnter);
			node.removeEventListener('dragover', onDragOver);
			node.removeEventListener('dragleave', onDragLeave);
			node.removeEventListener('drop', onDrop);
		}
	};
}
