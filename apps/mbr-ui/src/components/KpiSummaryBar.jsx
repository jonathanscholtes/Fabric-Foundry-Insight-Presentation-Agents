import { useKpis } from '../hooks/useKpis'

function fmtUSD(v)   { return v >= 1e6 ? `$${(v / 1e6).toFixed(2)}M` : `$${(v / 1e3).toFixed(0)}K` }
function fmtPct(v)   { return `${v.toFixed(1)}%` }
function fmtMiles(v) { return v >= 1e6 ? `${(v / 1e6).toFixed(2)}M` : `${(v / 1e3).toFixed(0)}K` }
function fmtCPM(v)   { return `$${v.toFixed(2)}` }

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

function getPriorLabel(period) {
  const [mon, yr] = (period || '').split(' ')
  const idx = MONTHS.indexOf(mon)
  if (idx === -1 || !yr) return 'prior'
  const pIdx = idx === 0 ? 11 : idx - 1
  const pYr  = idx === 0 ? parseInt(yr) - 1 : parseInt(yr)
  const last = new Date(pYr, pIdx + 1, 0).getDate()
  return `${MONTHS[pIdx]} 1 – ${MONTHS[pIdx]} ${last}`
}

function seededRand(seed) {
  let x = Math.sin(seed + 1) * 10000
  return () => { x = Math.sin(x) * 10000; return x - Math.floor(x) }
}

function Sparkline({ direction = 'neutral', seed = 1, color = '#22c55e', label = '' }) {
  const rand = seededRand(seed)
  const n    = 10
  let v      = direction === 'up' ? 0.28 : direction === 'down' ? 0.72 : 0.5
  const pts  = Array.from({ length: n }, () => {
    const bias = direction === 'up' ? 0.055 : direction === 'down' ? -0.055 : 0
    v = Math.max(0.05, Math.min(0.95, v + (rand() - 0.45) * 0.2 + bias))
    return v
  })

  const W = 72, H = 28
  const min = Math.min(...pts), max = Math.max(...pts)
  const range = max - min || 0.1
  const xy   = pts.map((p, i) => [
    (i / (n - 1)) * W,
    H - 4 - ((p - min) / range) * (H - 10),
  ])
  const line = xy.map((c, i) => `${i ? 'L' : 'M'}${c[0].toFixed(1)},${c[1].toFixed(1)}`).join('')
  const fill = `${line}L${W},${H}L0,${H}Z`
  const gId  = `spark-${label.replace(/[^a-z]/gi, '').toLowerCase()}`

  return (
    <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} className="kpi-sparkline">
      <defs>
        <linearGradient id={gId} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%"   stopColor={color} stopOpacity="0.22" />
          <stop offset="100%" stopColor={color} stopOpacity="0"    />
        </linearGradient>
      </defs>
      <path d={fill} fill={`url(#${gId})`} />
      <path d={line} fill="none" stroke={color} strokeWidth="1.5"
            strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function KpiCard({ label, metric, format, color, sparkSeed, priorLabel }) {
  if (!metric) {
    return (
      <div className="kpi-card">
        <span className="kpi-label">{label}</span>
        <span className="kpi-value">—</span>
      </div>
    )
  }

  const { value, delta_pct, delta_pp, direction } = metric
  const formatted  = value == null ? '—' : format(value)
  const delta      = delta_pct ?? delta_pp
  const deltaClass = direction === 'up' ? 'positive' : direction === 'down' ? 'negative' : ''
  const arrow      = direction === 'up' ? '↑' : direction === 'down' ? '↓' : ''
  const deltaLabel = delta_pp != null ? 'pp' : '%'

  return (
    <div className="kpi-card">
      <span className="kpi-label">{label}</span>
      <span className="kpi-value">{formatted}</span>
      {delta != null && (
        <span className={`kpi-delta ${deltaClass}`}>
          {arrow} {Math.abs(delta).toFixed(1)}{deltaLabel} vs {priorLabel}
        </span>
      )}
      <Sparkline direction={direction} seed={sparkSeed} color={color} label={label} />
    </div>
  )
}

export default function KpiSummaryBar({ period, region }) {
  const { data, isLoading, isError } = useKpis(period, region)
  const priorLabel = getPriorLabel(period)

  if (!period || !region) return null

  if (isLoading) {
    return (
      <div className="kpi-bar kpi-bar--loading">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="kpi-card kpi-card--skeleton skeleton" />
        ))}
      </div>
    )
  }

  if (isError || !data) {
    return <div className="kpi-bar kpi-bar--error">KPI data unavailable — Lakehouse may not be seeded for this period.</div>
  }

  return (
    <div className="kpi-bar">
      <KpiCard label="Operating Revenue" metric={data.total_revenue}        format={fmtUSD}   color="#3b82f6" sparkSeed={1.1} priorLabel={priorLabel} />
      <KpiCard label="Total Miles"       metric={data.total_miles}          format={fmtMiles} color="#22c55e" sparkSeed={2.3} priorLabel={priorLabel} />
      <KpiCard label="Empty Miles %"     metric={data.empty_miles_pct}      format={fmtPct}   color="#f59e0b" sparkSeed={3.7} priorLabel={priorLabel} />
      <KpiCard label="Operating Margin"  metric={data.operating_margin_pct} format={fmtPct}   color="#22c55e" sparkSeed={4.2} priorLabel={priorLabel} />
      <KpiCard label="Cost Per Mile"     metric={data.cost_per_mile}        format={fmtCPM}   color="#f59e0b" sparkSeed={5.8} priorLabel={priorLabel} />
      <KpiCard label="On-Time Delivery"  metric={data.on_time_delivery_pct} format={fmtPct}   color="#a855f7" sparkSeed={6.4} priorLabel={priorLabel} />
    </div>
  )
}
