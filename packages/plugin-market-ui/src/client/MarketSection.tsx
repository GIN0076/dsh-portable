/**
 * Plugin market settings section: search the npm registry through the host
 * loopback routes (/dsh-market/*), show results, and install through the M2
 * security gate. Mirrors the host route response shapes in lib/index.js.
 */
import { useCallback, useState } from 'react'
import { Button, IconLoadingOutline16, IconSearch16, IconWarningOutline16 } from '@deepseek-ai/dsh-client-ui-primitives'
import css from './MarketSection.module.css'

/** Mirrors the host route response shapes (lib/index.js). */
interface SearchResult {
  name: string
  version: string
  description?: string
  publisher?: string
}
interface InfoResult {
  name: string
  latest: string
  license?: string
  description?: string
  repository?: string
  dependencies?: Record<string, string>
}
interface InstallResult {
  ok: boolean
  status?: 'installed' | 'needs-approval' | 'rejected' | 'error'
  detail?: string
}
interface InstalledResult {
  ok: boolean
  plugins?: Array<{ name: string; version: string }>
}

/** Localized text function from ctx.locale.bind(). */
type Translate = (key: string) => string

export function MarketSection(props: { t: Translate }) {
  const { t } = props
  const [query, setQuery] = useState('')
  const [searching, setSearching] = useState(false)
  const [results, setResults] = useState<SearchResult[] | null>(null)
  const [installed, setInstalled] = useState<InstalledResult['plugins']>([])
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<SearchResult | null>(null)
  const [info, setInfo] = useState<InfoResult | null>(null)
  const [installing, setInstalling] = useState(false)
  const [installMsg, setInstallMsg] = useState<string | null>(null)
  const [approvalDetail, setApprovalDetail] = useState<string | null>(null)

  const refreshInstalled = useCallback(async () => {
    try {
      const res = await fetch('/dsh-market/installed')
      const data = (await res.json()) as InstalledResult
      if (res.ok) setInstalled(data.plugins || [])
    } catch {
      // ignore; the installed list is best-effort
    }
  }, [])

  const runSearch = useCallback(async () => {
    const q = query.trim()
    if (!q) return
    setSearching(true)
    setError(null)
    setResults(null)
    setSelected(null)
    setInfo(null)
    setInstallMsg(null)
    setApprovalDetail(null)
    try {
      const res = await fetch(`/dsh-market/search?q=${encodeURIComponent(q)}`)
      const data = await res.json()
      if (!res.ok) throw new Error(data?.error || data?.detail || `HTTP ${res.status}`)
      setResults(data.packages || [])
    } catch (err) {
      setError(String(err instanceof Error ? err.message : err))
    } finally {
      setSearching(false)
    }
  }, [query])

  const openInfo = useCallback(async (pkg: SearchResult) => {
    setSelected(pkg)
    setInfo(null)
    setInstallMsg(null)
    setApprovalDetail(null)
    try {
      const res = await fetch(`/dsh-market/info?pkg=${encodeURIComponent(pkg.name)}`)
      const data = await res.json()
      if (!res.ok) throw new Error(data?.error || data?.detail || `HTTP ${res.status}`)
      setInfo(data)
    } catch (err) {
      setError(String(err instanceof Error ? err.message : err))
    }
  }, [])

  const doInstall = useCallback(async (approve: string[] = []) => {
    if (!selected) return
    if (!approve.length && !window.confirm(t('confirmInstall').replace('{name}', selected.name))) return
    setInstalling(true)
    setInstallMsg(null)
    setApprovalDetail(null)
    try {
      const res = await fetch('/dsh-market/install', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ pkg: selected.name, approve }),
      })
      const data = (await res.json()) as InstallResult
      if (res.status === 409 && data.status === 'needs-approval') {
        setApprovalDetail(data.detail || t('needsApproval'))
        return
      }
      if (!res.ok) {
        if (data.status === 'rejected') { setInstallMsg(t('rejected')); return }
        throw new Error(data?.detail || data?.error || `HTTP ${res.status}`)
      }
      setInstallMsg(t('installedOk').replace('{name}', selected.name))
      await refreshInstalled()
    } catch (err) {
      setError(String(err instanceof Error ? err.message : err))
    } finally {
      setInstalling(false)
    }
  }, [selected, t, refreshInstalled])

  const installedNames = new Set((installed || []).map((p) => p.name))

  return (
    <div className={css.root}>
      <h2 className={css.title}>{t('nav')}</h2>
      <p className={css.sub}>{t('subtitle')}</p>
      <div className={css.searchRow}>
        <input
          className={css.searchInput}
          value={query}
          placeholder={t('searchPlaceholder')}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => { if (event.key === 'Enter') runSearch() }}
        />
        <Button variant="primary" onClick={runSearch} disabled={searching} icon={searching ? <IconLoadingOutline16 /> : <IconSearch16 />}>
          {searching ? t('searching') : t('search')}
        </Button>
      </div>

      {error !== null && <div className={css.error}>{t('error')}: {error}</div>}
      {installMsg !== null && <div className={css.ok}>{installMsg}</div>}

      {results !== null && results.length === 0 && <div className={css.warn}>{t('noResults')}</div>}
      {results !== null && results.length > 0 && (
        <div className={css.result}>
          {results.map((pkg) => (
            <div key={pkg.name} className={css.row}>
              <div>
                <div className={css.name}>{pkg.name}</div>
                <div className={css.meta}>{pkg.version}</div>
              </div>
              <div className={css.actions}>
                <Button onClick={() => openInfo(pkg)}>{t('detail')}</Button>
                {installedNames.has(pkg.name)
                  ? <span className={css.ok}>{t('installed')}</span>
                  : <Button variant="primary" disabled={installing && selected?.name === pkg.name} onClick={() => { setSelected(pkg); setInfo(null); setApprovalDetail(null); doInstall([]) }}>
                      {installing && selected?.name === pkg.name ? t('installing') : t('install')}
                    </Button>}
              </div>
            </div>
          ))}
        </div>
      )}

      {selected !== null && (
        <div className={css.result}>
          <div className={css.row}>
            <div className={css.name}>{selected.name}</div>
            <Button onClick={() => { setSelected(null); setInfo(null); setApprovalDetail(null) }}>{t('close')}</Button>
          </div>
          {info !== null && (
            <>
              <div className={css.line}>{t('latest')}: <b>{info.latest}</b></div>
              {info.license && <div className={css.line}>{t('license')}: {info.license}</div>}
              {info.description && <p className={css.desc}>{info.description}</p>}
              {info.repository && <div className={css.line}>{t('repository')}: {info.repository}</div>}
              {info.dependencies && Object.keys(info.dependencies).length > 0 && (
                <div className={css.line}>{t('dependencies')}: {Object.entries(info.dependencies).map(([k, v]) => `${k}@${v}`).join(', ')}</div>
              )}
            </>
          )}
          {approvalDetail !== null && (
            <div className={css.warn}>
              {t('needsApproval')}
              <pre className={css.error}>{approvalDetail}</pre>
              <Button variant="primary" disabled={installing} onClick={() => doInstall(['INSTALL-SCRIPT', 'NET-EGRESS', 'CHILD-PROC', 'SESSION-READ', 'FILE-WRITE', 'DEP-VULN'])}>
                {installing ? t('installing') : t('approveAll')}
              </Button>
            </div>
          )}
          {installing && <div className={css.warn}>{t('installing')}</div>}
        </div>
      )}

      {installed !== null && installed.length > 0 && (
        <div className={css.result}>
          <div className={css.line}>{t('installed')}: {installed.map((p) => `${p.name}@${p.version}`).join(', ')}</div>
        </div>
      )}
      {installed !== null && installed.length === 0 && <div className={css.hint}>{t('emptyInstalled')}</div>}
    </div>
  )
}
