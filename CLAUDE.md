# CLAUDE.md

## Architecture
- **frontend/**: SvelteKit 2 + Svelte 5 app with Tailwind CSS v4, static adapter
- **backend/**: Bun + Elysia API server with Drizzle ORM + PostgreSQL

## Commands
| Task | Frontend (`cd frontend`) | Backend (`cd backend`) |
|------|--------------------------|------------------------|
| Dev | `bun run dev` | `bun --watch src/index.ts` |
| Build | `bun run build` | `bun build src/index.ts --target bun --outdir ./dist` |
| Lint | `bun run lint` | — |
| Format | `bun run format` | — |
| Typecheck | `bun run check` | — |
| Test | — | `bun test` (single: `bun test <file>`) |

## Code Style
- Use tabs, single quotes, no trailing commas (Prettier configured in frontend)
- Frontend: Svelte 5 runes, TypeScript strict, Lucide icons
- Backend: Drizzle schemas in `schemas/`, snake_case for DB columns, camelCase in TS
- No comments unless complex; no `// @ts-expect-error` or `as any`

## UI Style Guide

### Buttons
All buttons should follow these patterns:

**Primary Button (filled)**
```html
class="px-4 py-2 bg-black text-white rounded-full font-bold hover:bg-gray-800 transition-all duration-200 disabled:opacity-50 cursor-pointer"
```

**Secondary Button (outlined) - Navigation/Action buttons**
```html
class="px-4 py-2 border-4 border-black rounded-full font-bold hover:border-dashed transition-all duration-200 disabled:opacity-50 cursor-pointer"
```

**Toggle/Filter Button (selected state)**
```html
class="px-4 py-2 border-4 border-black rounded-full font-bold transition-all duration-200 cursor-pointer {isSelected
    ? 'bg-black text-white'
    : 'hover:border-dashed'}"
```

### Cards & Containers
```html
class="border-4 border-black rounded-2xl p-6 hover:border-dashed transition-all"
```

### Inputs
```html
class="w-full px-4 py-2 border-2 border-black rounded-lg focus:outline-none focus:border-dashed"
```

### Modals
```html
class="bg-white rounded-2xl w-full max-w-lg p-6 border-4 border-black max-h-[90vh] overflow-y-auto"
```

### Confirmation Modals
Use the `ConfirmModal` component from `$lib/components/ConfirmModal.svelte` or follow this pattern:

**Backdrop**
```html
<div
    class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4"
    onclick={(e) => e.target === e.currentTarget && onCancel()}
    onkeydown={(e) => e.key === 'Escape' && onCancel()}
    role="dialog"
    tabindex="-1"
>
```

**Modal Container**
```html
class="bg-white rounded-2xl w-full max-w-md p-6 border-4 border-black"
```

**Title**
```html
<h2 class="text-2xl font-bold mb-4">{title}</h2>
```

**Message**
```html
<p class="text-gray-600 mb-6">{message}</p>
```

**Button Row**
```html
<div class="flex gap-3">
    <!-- Cancel button (secondary) -->
    <button class="flex-1 px-4 py-2 border-4 border-black rounded-full font-bold hover:border-dashed transition-all duration-200 disabled:opacity-50 cursor-pointer">
        cancel
    </button>
    <!-- Confirm button (primary/success/warning/danger) -->
    <button class="flex-1 px-4 py-2 bg-black text-white rounded-full font-bold border-4 border-black hover:border-dashed transition-all duration-200 disabled:opacity-50 cursor-pointer">
        confirm
    </button>
</div>
```

**Confirm Button Variants**
- Primary: `bg-black text-white`
- Success: `bg-green-600 text-white`
- Warning: `bg-yellow-500 text-white`
- Danger: `bg-red-600 text-white`

**Do NOT use browser `alert()` or `confirm()`. Always use styled modals.**

### Key Patterns
- **Border style**: `border-4` for buttons, `border-2` for inputs, `border-4` for cards/containers
- **Rounding**: `rounded-full` for buttons, `rounded-2xl` for cards, `rounded-lg` for inputs
- **Hover state**: `hover:border-dashed` for outlined elements
- **Focus state**: `focus:border-dashed` for inputs
- **Selected state**: `bg-black text-white` (filled)
- **Animation**: Always include `transition-all duration-200`
- **Colors**: Black borders, white backgrounds, no colors except for errors (red)
- **Cursor**: Always include `cursor-pointer` on clickable elements (buttons, links, interactive cards)
- **Disabled cursor**: Always include `disabled:cursor-not-allowed` on buttons that can be disabled
