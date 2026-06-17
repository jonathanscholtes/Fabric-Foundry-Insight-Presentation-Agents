import { useKpis } from '../hooks/useKpis';

function KpiCard({ label, value, delta, format }) {
  const formatted = value == null ? '—' : format(value);
  const sign = delta == null ? null : delta >= 0 ? '+' : '';
  return (
    <div className="kpi-card">
      <span className="kpi-label">{label}</span>
      <span className="kpi-value">{formatted}</span>
      {delta != null && (
        <span className={`kpi-delta ${delta >= 0 ? 'positive' : 'negative'}`}>
          {sign}{delta.toFixed(1)}%
        </span>
      )}
    </div>
  );
}

function fmtUSD(v) {
  if (v >= 1e6) return `$${(v / 1e6).toFixed(2)}M`;
  return `$${(v / 1e3).toFixed(0)}K`;
}

function fmtPct(v) { return `${v.toFixed(1)}%`; }

function fmtMiles(v) {
  if (v >= 1e6) return `${(v / 1e6).toFixed(2)}M`;
  return `${(v / 1e3).toFixed(0)}K`;
}

export default function KpiSummaryBar({ period, region }) {
  const { data, isLoading, isError } = useKpis(period, region);

  if (!period || !region) return null;

  if (isLoading) {
    return (
      <div className="kpi-bar kpi-bar--loading">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="kpi-card kpi-card--skeleton" />
        ))}
      </div>
    );
  }

  if (isError || !data) {
    return <div className="kpi-bar kpi-bar--error">Failed to load KPIs.</div>;
  }

  const kpis = data.kpis ?? data;

  return (
    <div className="kpi-bar">
      <KpiCard label="Revenue"        value={kpis.total_revenue}       delta={kpis.revenue_delta_pct}    format={fmtUSD}   />
      <KpiCard label="Total Cost"     value={kpis.total_cost}          delta={kpis.cost_delta_pct}       format={fmtUSD}   />
      <KpiCard label="Operating Ratio" value={kpis.operating_ratio}    delta={kpis.or_delta_pct}         format={fmtPct}   />
      <KpiCard label="On-Time %"      value={kpis.on_time_pct}         delta={kpis.on_time_delta_pct}    format={fmtPct}   />
      <KpiCard label="Miles"          value={kpis.total_miles}         delta={kpis.miles_delta_pct}      format={fmtMiles} />
      <KpiCard label="Fleet Util %"   value={kpis.fleet_utilization_pct} delta={kpis.util_delta_pct}    format={fmtPct}   />
    </div>
  );
}
