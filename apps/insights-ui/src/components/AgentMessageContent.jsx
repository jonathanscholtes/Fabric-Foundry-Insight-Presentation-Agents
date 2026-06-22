import EfficiencyDonut from './charts/EfficiencyDonut'
import ServiceBarChart from './charts/ServiceBarChart'

export default function AgentMessageContent({ content, key_drivers, analytics }) {
  const hasStructured = (key_drivers?.length > 0) || analytics

  if (!hasStructured) {
    return <span className="message-content">{content}</span>
  }

  // Revenue trend and the overall bottom-line summary are intentionally NOT
  // rendered here — they live permanently in the dashboard's Analytics panel.
  // The chat answers the specific question; it does not restate the dashboard.
  const serviceData = analytics?.service_performance?.data?.map(d => ({
    vehicle_type: d.label,
    pct: d.value,
  }))

  const efficiencyValue = analytics?.operational_efficiency?.value

  return (
    <div className="message-content" style={{ padding: 0, overflow: 'hidden' }}>

      <div style={{ padding: '10px 14px 8px' }}>
        <p className="analytics-narrative" style={{ margin: 0 }}>{content}</p>
      </div>

      {key_drivers?.length > 0 && (
        <div style={{ margin: '0 14px 10px', borderTop: '1px solid var(--border)', paddingTop: 8 }}>
          <div className="key-drivers-heading">Key Drivers</div>
          {key_drivers.map((d, i) => (
            <div key={i} className="key-driver-row">
              <span className="key-driver-label">{d.label}</span>
              <span className={`key-driver-value ${d.direction}`}>{d.value}</span>
            </div>
          ))}
        </div>
      )}

      {analytics && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, padding: '0 14px 12px' }}>
          {analytics.cost_management?.narrative && (
            <div className="analytics-card">
              <div className="analytics-card-title">Cost Management</div>
              <p className="analytics-narrative">{analytics.cost_management.narrative}</p>
            </div>
          )}

          {efficiencyValue != null && efficiencyValue > 0 && (
            <div className="analytics-card">
              <div className="analytics-card-title">Operational Efficiency</div>
              <div className="analytics-donut-row">
                <div className="analytics-donut-item">
                  <EfficiencyDonut value={efficiencyValue} />
                  <span className="analytics-donut-label">On-Time Rate</span>
                </div>
              </div>
            </div>
          )}

          {serviceData?.length > 0 && (
            <div className="analytics-card">
              <div className="analytics-card-title">Service Performance</div>
              <ServiceBarChart data={serviceData} />
            </div>
          )}
        </div>
      )}
    </div>
  )
}
