/**
 * The update-check settings section: one button that runs the host route
 * /dsh-update/check (which executes addons/update-engine/update-dsh.ps1 in
 * check mode) and shows the result inline.
 */
import { useCallback, useState } from 'react'
import { Button, IconLoadingOutline16, IconRefreshOutline14 } from '@deepseek-ai/dsh-client-ui-primitives'
import css from './UpdateSection.module.css'

/** Mirrors the host route response shape (lib/index.js). */
interface UpdateResult {
  status: 'up-to-date' | 'update-available' | 'error' | string
  current: string
  latest: string
  tag?: string
  detail?: string
}

/** Localized text function from ctx.locale.bind(). */
type Translate = (key: string) => string

export function UpdateSection(props: { t: Translate }) {
  const { t } = props
  const [checking, setChecking] = useState(false)
  const [result, setResult] = useState<UpdateResult | null>(null)
  const [error, setError] = useState<string | null>(null)

  const run = useCallback(async () => {
    setChecking(true)
    setError(null)
    setResult(null)
    try {
      const res = await fetch('/dsh-update/check')
      const data = (await res.json()) as UpdateResult
      if (!res.ok) throw new Error(data?.detail || `HTTP ${res.status}`)
      setResult(data)
    } catch (err) {
      setError(String(err instanceof Error ? err.message : err))
    } finally {
      setChecking(false)
    }
  }, [])

  return (
    <div className={css.root}>
      <h2 className={css.title}>{t('nav')}</h2>
      <p className={css.sub}>{t('subtitle')}</p>
      <div className={css.actions}>
        <Button
          variant="primary"
          onClick={run}
          disabled={checking}
          icon={checking ? <IconLoadingOutline16 /> : <IconRefreshOutline14 />}
        >
          {checking ? t('checking') : t('check')}
        </Button>
      </div>
      {error !== null && <div className={css.error}>{t('error')}: {error}</div>}
      {result !== null && (
        <div className={css.result}>
          <div className={css.line}>{t('current')}: <b>{result.current}</b></div>
          <div className={css.line}>{t('latest')}: <b>{result.latest}</b></div>
          {result.status === 'up-to-date' && <div className={css.ok}>{t('upToDate')}</div>}
          {result.status === 'update-available' && <div className={css.warn}>{t('updateAvailable')}</div>}
          {result.status === 'error' && <div className={css.error}>{t('error')}</div>}
          {result.status === 'update-available' && (
            <div className={css.hint}>{t('hint')}</div>
          )}
        </div>
      )}
    </div>
  )
}
