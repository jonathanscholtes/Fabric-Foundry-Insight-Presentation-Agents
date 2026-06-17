import { useAnalytics } from '../hooks/useAnalytics';
import RevenueLineChart from './charts/RevenueLineChart';
import EfficiencyDonut from './charts/EfficiencyDonut';
import ServiceBarChart from './charts/ServiceBarChart';

export default function AnalyticsPanel({ period, region }) {
  const { data, isLoading, isError } = useAnalytics(period, region);

  if (!period || !region) return null;

  if (isLoading) {
    return <div className="analytics-panel analytics-panel--loading">Loading analytics…</div>;
  }

  if (isError || !data) {
    return <div className="analytics-panel analytics-panel--error">Failed to load analytics.</div>;
  }

  return (
    <div className="analytics-panel">
      <section className="analytics-section">
        <h3 className="analytics-section-title">Revenue Trend</h3>
        <RevenueLineChart data={data.revenue_trend} />
      </section>

      <section className="analytics-section">
        <h3 className="analytics-section-title">Fleet Efficiency</h3>
        <div className="analytics-donut-row">
          <div className="analytics-donut-item">
            <EfficiencyDonut value={data.fleet_utilization_pct} />
            <span className="analytics-donut-label">Fleet Util.</span>
          </div>
          <div className="analytics-donut-item">
            <EfficiencyDonut value={data.on_time_pct} />
            <span className="analytics-donut-label">On-Time</span>
          </div>
          <div className="analytics-donut-item">
            <EfficiencyDonut value={data.loaded_mile_pct} />
            <span className="analytics-donut-label">Loaded Mile %</span>
          </div>
        </div>
      </section>

      <section className="analytics-section">
        <h3 className="analytics-section-title">On-Time by Vehicle Type</h3>
        <ServiceBarChart data={data.on_time_by_vehicle} />
      </section>
    </div>
  );
}
