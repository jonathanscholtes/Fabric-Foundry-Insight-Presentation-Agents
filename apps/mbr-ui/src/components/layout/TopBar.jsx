const PERIODS = [
  'May 2025', 'Apr 2025', 'Mar 2025', 'Feb 2025', 'Jan 2025',
  'Dec 2024', 'Nov 2024', 'Oct 2024', 'Sep 2024', 'Aug 2024',
  'Jul 2024', 'Jun 2024', 'May 2024',
]

const REGIONS = [
  { label: 'All Regions', value: 'All'     },
  { label: 'North',       value: 'North'   },
  { label: 'South',       value: 'South'   },
  { label: 'East',        value: 'East'    },
  { label: 'West',        value: 'West'    },
  { label: 'Central',     value: 'Central' },
]

const MON_ABBR = { Jan:1, Feb:2, Mar:3, Apr:4, May:5, Jun:6, Jul:7, Aug:8, Sep:9, Oct:10, Nov:11, Dec:12 }

function formatPeriodRange(period) {
  const [mon, yr] = (period || '').split(' ')
  const m = MON_ABBR[mon]
  if (!m || !yr) return period
  const last = new Date(parseInt(yr), m, 0).getDate()
  return `${mon} 1 – ${mon} ${last}, ${yr}`
}

function CalendarIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none"
         stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
      <line x1="16" y1="2" x2="16" y2="6"/>
      <line x1="8"  y1="2" x2="8"  y2="6"/>
      <line x1="3"  y1="10" x2="21" y2="10"/>
    </svg>
  )
}

function DatabaseIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none"
         stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <ellipse cx="12" cy="5" rx="9" ry="3"/>
      <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>
      <path d="M3 12c0 1.66 4 3 9 3s9-1.34 9-3"/>
    </svg>
  )
}

function ChevronDown() {
  return (
    <svg width="10" height="10" viewBox="0 0 24 24" fill="none"
         stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="6,9 12,15 18,9"/>
    </svg>
  )
}

function DotsIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
      <circle cx="5"  cy="12" r="2"/>
      <circle cx="12" cy="12" r="2"/>
      <circle cx="19" cy="12" r="2"/>
    </svg>
  )
}

export default function TopBar({ period, region, onPeriod, onRegion }) {
  const connectedCount = region === 'All' ? 5 : 1
  const regionLabel    = region === 'All' ? 'All Regions' : `${region} Region`

  return (
    <div className="topbar">
      <div className="topbar-title-block">
        <span className="topbar-title">MBR Creation &amp; Analysis</span>
        <span className="topbar-subtitle">
          Analyze performance and generate a management presentation that drives decisions.
        </span>
      </div>

      <div className="topbar-controls">

        {/* Period pill */}
        <div className="topbar-pill">
          <span className="topbar-pill-icon"><CalendarIcon /></span>
          <div className="topbar-pill-inner">
            <span className="topbar-label">MBR Period</span>
            <span className="topbar-pill-value">{formatPeriodRange(period)}</span>
          </div>
          <span className="topbar-pill-chevron"><ChevronDown /></span>
          <select
            className="topbar-pill-select"
            value={period}
            onChange={e => onPeriod(e.target.value)}
            aria-label="MBR Period"
          >
            {PERIODS.map(p => <option key={p} value={p}>{p}</option>)}
          </select>
        </div>

        <div className="topbar-divider" />

        {/* Data sources pill */}
        <div className="topbar-pill">
          <span className="topbar-pill-icon"><DatabaseIcon /></span>
          <div className="topbar-pill-inner">
            <span className="topbar-label">Data Sources</span>
            <div className="topbar-datasource-row">
              <span className="topbar-datasource-dot" />
              <span className="topbar-pill-value">{connectedCount} Connected · {regionLabel}</span>
            </div>
          </div>
          <span className="topbar-pill-chevron"><ChevronDown /></span>
          <select
            className="topbar-pill-select"
            value={region}
            onChange={e => onRegion(e.target.value)}
            aria-label="Data Source Region"
          >
            {REGIONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
          </select>
        </div>

        <button className="topbar-more-btn" aria-label="More options">
          <DotsIcon />
        </button>

      </div>
    </div>
  )
}
