// Generate last 13 months as period options
function buildPeriodOptions() {
  const months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ]
  const options = []
  const now = new Date()
  for (let i = 0; i < 13; i++) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
    const label = `${months[d.getMonth()]} ${d.getFullYear()}`
    const value = `${months[d.getMonth()]}${d.getFullYear()}`
    options.push({ label, value })
  }
  return options
}

const PERIOD_OPTIONS = buildPeriodOptions()

const REGION_OPTIONS = [
  { label: 'All Regions', value: 'All' },
  { label: 'Northeast',   value: 'Northeast' },
  { label: 'Southeast',   value: 'Southeast' },
  { label: 'Midwest',     value: 'Midwest' },
  { label: 'Southwest',   value: 'Southwest' },
  { label: 'West',        value: 'West' },
]

export default function TopBar({ period, region, onPeriod, onRegion }) {
  return (
    <div className="topbar">
      <div className="topbar-title-block">
        <span className="topbar-title">MBR Creation &amp; Analysis</span>
        <span className="topbar-subtitle">
          Analyze performance and generate a management presentation that drives decisions.
        </span>
      </div>

      <div className="topbar-controls">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <label className="topbar-label">MBR Period</label>
          <select
            className="topbar-select"
            value={period}
            onChange={e => onPeriod(e.target.value)}
          >
            {PERIOD_OPTIONS.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <label className="topbar-label">Data Source</label>
          <select
            className="topbar-select"
            value={region}
            onChange={e => onRegion(e.target.value)}
          >
            {REGION_OPTIONS.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>
      </div>
    </div>
  )
}
