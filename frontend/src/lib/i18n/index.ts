import { readable } from 'svelte/store';
import en from './en';

export type Locale = 'en';
type DeepStringify<T> = { [K in keyof T]: T[K] extends string ? string : DeepStringify<T[K]> };
export type Translations = DeepStringify<typeof en>;

export const locale = readable<Locale>('en');
export const t = readable<Translations>(en);
