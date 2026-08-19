/**
 * The update-check settings section: a "check" button that runs the host
 * route /dsh-update/check (addons/update-engine/update-dsh.ps1 check mode),
 * and — when an update is available — an "Update now" button that POSTs to
 * /dsh-update/apply (apply mode, stopped by the updater mid-flight).
 */
import { useCallback, useState } from 'react'
import { Button, IconLoadingOutline16, IconRefreshOutline14, IconWarningOutline16 } from '@deepseek-ai/dsh-client-ui-primitives'
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
  const [applying, setApplying] = useState(false)
  const [applyFailed, setApplyFailed] = useState<string | null>(null)

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

  const apply = useCallback(async () => {
    if (!window.confirm(t('confirmApply'))) return
    setApplyFailed(null)
    setApplying(true)
    try {
      const res = await fetch('/dsh-update/apply', { method: 'POST' })
      const data = (await res.json()) as { status?: string; error?: string; detail?: string }
      if (!res.ok) throw new Error(data?.error || data?.detail || `HTTP ${res.status}`)
      if (data?.status !== 'started') throw new Error(data?.detail || 'unexpected response')
      // The updater stops this very service; keep the "started" message up.
    } catch (err) {
      setApplying(false)
      setApplyFailed(t('applyFailed') + ': ' + String(err instanceof Error ? err.message : err))
    }
  }, [t])

  const showApply = result !== null && result.status === 'update-available' && !applying

  return (
    <div className={css.root}>
      <h2 className={css.title}>{t('nav')}</h2>
      <p className={css.sub}>{t('subtitle')}</p>
      <div className={css.actions}>
        <Button
          variant="primary"
          onClick={run}
          disabled={checking || applying}
          icon={checking ? <IconLoadingOutline16 /> : <IconRefreshOutline14 />}
        >
          {checking ? t('checking') : t('check')}
        </Button>
        {showApply && (
          <Button
            variant="primary"
            onClick={apply}
            icon={<IconWarningOutline16 />}
          >
            {t('apply')}
          </Button>
        )}
      </div>
      {error !== null && <div className={css.error}>{t('error')}: {error}</div>}
      {applyFailed !== null && <div className={css.error}>{applyFailed}</div>}
      {applying && <div className={css.warn}>{t('applying')}</div>}
      {applying && <div className={css.result}><div className={css.line}>{t('applyStarted')}</div></div>}
      {result !== null && !applying && (
        <div className={css.result}>
          <div className={css.line}>{t('current')}: <b>{result.current}</b></div>
          <div className={css.line}>{t('latest')}: <b>{result.latest}</b></div>
          {result.status === 'up-to-date' && <div className={css.ok}>{t('upToDate')}</div>}
          {result.status === 'update-available' && <div className={css.warn}>{t('updateAvailable')}</div>}
          {result.status === 'error' && <div className={css.error}>{t('error')}</div>}
        </div>
      )}
    </div>
  )
}
