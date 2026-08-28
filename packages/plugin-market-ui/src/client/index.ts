/**
 * dsh-market-ui client: registers a "Plugin Market" settings section that
 * drives the host loopback routes (/dsh-market/*). Built by tsdown into the
 * __ModuleLoader__ factory bundle at client/client.js; the only externals are
 * the loader module table's react entries.
 */
import { createElement as h } from 'react'
import * as primitives from '@deepseek-ai/dsh-client-ui-primitives'
import { en, zh } from './locales.ts'
import { MarketSection } from './MarketSection.tsx'

const NS = 'dsh-market-ui'

/** Primitives this bundle relies on. If the host resolves the primitives
 * module but lacks one, skip registration rather than blank the dialog. */
export const REQUIRED_PRIMITIVES = ['Button', 'IconLoadingOutline16', 'IconSearch16', 'IconWarningOutline16'] as const

export function missingPrimitives(mod: Record<string, unknown>, required: readonly string[] = REQUIRED_PRIMITIVES): string[] {
  return required.filter(name => mod[name] === undefined)
}

/** Localized text function. */
type Translate = (key: string) => string

/** The subset of the slots/locale services this plugin touches. */
interface SlotsService {
  inject(slot: string, register: () => unknown): void
  register(meta: Record<string, unknown>, component: () => unknown): unknown
}
interface LocaleService {
  register(namespace: string, dicts: { zh: Record<string, string>; en: Record<string, string> }): unknown
  bind(namespace: string): Translate
}

/** The client cordis context shape this plugin relies on (structural typing). */
interface MarketClientContext {
  effect(callback: () => unknown, label?: string): void
  locale: LocaleService
  slots: SlotsService
}

export const name = 'dsh-market-ui'
export const inject = ['slots', 'locale']

export function apply(ctx: MarketClientContext): void {
  const gaps = missingPrimitives(primitives as unknown as Record<string, unknown>)
  if (gaps.length > 0) {
    console.warn(`[dsh-market-ui] host ui-primitives missing ${gaps.join(', ')} — market section disabled`)
    return
  }

  ctx.effect(() => ctx.locale.register(NS, { zh, en }), 'dsh-market-ui: dictionaries')
  const t = ctx.locale.bind(NS)

  ctx.slots.inject('settings.section', () => ctx.slots.register({
    name: 'settings.section',
    id: 'dsh-market-ui',
    order: 70,
    label: () => t('nav'),
    locale: NS,
    inject: () => ({ t }),
  }, () => h(MarketSection, { t })))
}
