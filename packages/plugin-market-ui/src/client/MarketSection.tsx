/**
 * Plugin market settings section: search the npm registry through the host
 * loopback routes (/dsh-market/*), filter by functional category, show
 * popularity/downloads, and install through the M2 security gate.
 */
import { useCallback, useMemo, useState } from 'react'
import { Button, IconLoadingOutline16, IconSearch16, IconWarningOutline16 } from '@deepseek-ai/dsh-client-ui-primitives'
import css from './MarketSection.module.css'

/** Mirrors the host route response shapes (lib/index.js + dsh-market.ps1 -Json). */
interface SearchResult {
  name: string
  version: string
  description?: string
  publisher?: string
  keywords?: string[]
  downloads?: number
  popularity?: number
}
interface InfoResult {
  name: string
  latest: string
  license?: string
  description?: string
  repository?: string
  keywords?: string[]
  downloads?: number
  popularity?: number
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

/** Functional categories derived from npm keywords. */
type Category = 'dsh' | 'agent' | 'tool' | 'ui' | 'memory' | 'other'

const CATEGORY_KEYWORDS: Record<Exclude<Category, 'other'>, string[]> = {
  dsh: ['dsh', 'dsh-plugin', 'deepseek', 'harness', 'cordis', 'marketplace'],
  agent: ['agent', 'agents', 'subagent', 'workflow', 'autonomous'],
  tool: ['tool', 'tools', 'mcp', 'integration'],
  ui: ['ui', 'theme', 'client', 'interface'],
  memory: ['memory', 'session', 'context', 'recall'],
}

function categoryOf(pkg: { keywords?: string[] }): Category {
  const kws = (pkg.keywords || []).map((k) => k.toLowerCase())
  for (const cat of Object.keys(CATEGORY_KEYWORDS) as Exclude<Category, 'other'>[]) {
    if (CATEGORY_KEYWORDS[cat].some((kw) => kws.includes(kw))) return cat
  }
  return 'other'
}

/** 12.3k / 1.4M formatting for downloads. */
function formatDownloads(n: number): string {
  if (!Number.isFinite(n) || n <= 0) return '0'
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`
  return String(Math.round(n))
}

/** ★★☆☆☆ from popularity (0..1). */
function stars(popularity: number | undefined): string {
  const p = Number.isFinite(popularity || 0) ? (popularity || 0) : 0
  const full = Math.round(p * 5)
  return '★'.repeat(full) + '☆'.repeat(5 - full)
}

/** Localized text function from ctx.locale.bind(). */
type Translate = (key: string) => string

export function MarketSection(props: { t: Translate }) {
  const { t } = props
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState<Category | 'all'>('all')
  const [searching, setSearching] = useState(false)
  const [results, setResults] = useState<SearchResult[] | null>(null)
  const [installed, setInstalled] = useState<InstalledResult['plugins']>([])
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<SearchResult | null>(null)
  const [info, setInfo] = useState<InfoResult | null>(null)
  const [installing, setInstalling] = useState(false)
  const [installMsg, setInstallMsg] = useState<string | null>(null)
  const [approvalDetail, setApprovalDetail] = useState<string | null>(null)

  const categoryKeys: Array<Category | 'all'> = useMemo(() => ['all', 'dsh', 'agent', 'tool', 'ui', 'memory', 'other'], [])
  const catLabel = (cat: Category | 'all'): string =>
    cat === 'all' ? t('all') : t(`cat${cat[0].toUpperCase()}${cat.slice(1)}`)

  const filtered = useMemo(() => {
    if (!results) return null
    if (category === 'all') return results
    return results.filter((pkg) => categoryOf(pkg) === category)
  }, [results, category])

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

      <div className={css.catRow}>
        {categoryKeys.map((cat) => (
          <button
            key={cat}
            type="button"
            className={`${css.catChip}${category === cat ? ` ${css.catChipActive}` : ''}`}
            onClick={() => setCategory(cat)}
          >
            {catLabel(cat)}
          </button>
        ))}
      </div>

      {error !== null && <div className={css.error}>{t('error')}: {error}</div>}
      {installMsg !== null && <div className={css.ok}>{installMsg}</div>}

      {filtered !== null && filtered.length === 0 && <div className={css.warn}>{t('noResults')}</div>}
      {filtered !== null && filtered.length > 0 && (
        <div className={css.result}>
          {filtered.map((pkg) => (
            <div key={pkg.name} className={css.row}>
              <div className={css.pkgInfo}>
                <div className={css.name}>
                  {pkg.name}
                  <span className={css.catTag}>{catLabel(categoryOf(pkg))}</span>
                </div>
                <div className={css.meta}>
                  {pkg.version}
                  {pkg.downloads !== undefined && <span className={css.metaSep}>· {t('downloads')} {formatDownloads(pkg.downloads)}</span>}
                  {pkg.popularity !== undefined && <span className={css.metaSep}>{stars(pkg.popularity)}</span>}
                </div>
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
              {info.downloads !== undefined && <div className={css.line}>{t('downloads')}: <b>{formatDownloads(info.downloads)}</b></div>}
              {info.popularity !== undefined && <div className={css.line}>{t('popularity')}: {stars(info.popularity)}</div>}
              {info.license && <div className={css.line}>{t('license')}: {info.license}</div>}
              {info.keywords && info.keywords.length > 0 && <div className={css.line}>{t('keywords')}: {info.keywords.join(', ')}</div>}
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
