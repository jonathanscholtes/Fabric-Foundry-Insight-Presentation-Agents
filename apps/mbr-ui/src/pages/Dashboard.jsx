import { useState } from 'react';
import KpiSummaryBar from '../components/KpiSummaryBar';
import ConversationPanel from '../components/ConversationPanel';
import AnalyticsPanel from '../components/AnalyticsPanel';
import PresentationPanel from '../components/PresentationPanel';
import { useConversation } from '../hooks/useConversation';

const PERIODS = [
  'May 2025', 'Apr 2025', 'Mar 2025', 'Feb 2025', 'Jan 2025',
  'Dec 2024', 'Nov 2024', 'Oct 2024', 'Sep 2024', 'Aug 2024',
  'Jul 2024', 'Jun 2024', 'May 2024',
];

const REGIONS = ['North', 'South', 'East', 'West', 'Central'];

export default function Dashboard() {
  const [period, setPeriod] = useState('May 2025');
  const [region, setRegion] = useState('North');

  const { threadId, messages, isPending, send } = useConversation(period, region);

  return (
    <div className="page-container">
      <header className="page-header">
        <div className="page-title">
          <h1>MBR Dashboard</h1>
          <span className="page-subtitle">Jonathan Scholtes</span>
        </div>
        <div className="page-filters">
          <select value={period} onChange={e => setPeriod(e.target.value)}>
            {PERIODS.map(p => <option key={p}>{p}</option>)}
          </select>
          <select value={region} onChange={e => setRegion(e.target.value)}>
            {REGIONS.map(r => <option key={r}>{r}</option>)}
          </select>
        </div>
      </header>

      <KpiSummaryBar period={period} region={region} />

      <div className="dashboard-grid">
        <section className="dashboard-cell dashboard-cell--analytics">
          <AnalyticsPanel period={period} region={region} />
        </section>

        <section className="dashboard-cell dashboard-cell--conversation">
          <h2 className="section-title">AI Assistant</h2>
          <ConversationPanel
            period={period}
            region={region}
            threadId={threadId}
            messages={messages}
            isPending={isPending}
            onSend={send}
          />
        </section>

        <section className="dashboard-cell dashboard-cell--presentation">
          <PresentationPanel period={period} region={region} />
        </section>
      </div>
    </div>
  );
}
