import { useState } from 'react';
import ConversationPanel from '../components/ConversationPanel';
import { useConversation } from '../hooks/useConversation';

const PERIODS = [
  'May 2025', 'Apr 2025', 'Mar 2025', 'Feb 2025', 'Jan 2025',
  'Dec 2024', 'Nov 2024', 'Oct 2024', 'Sep 2024', 'Aug 2024',
  'Jul 2024', 'Jun 2024', 'May 2024',
];

const REGIONS = ['North', 'South', 'East', 'West', 'Central'];

export default function Conversations() {
  const [period, setPeriod] = useState('May 2025');
  const [region, setRegion] = useState('North');

  const { threadId, messages, isPending, send } = useConversation(period, region);

  return (
    <div className="page-container">
      <header className="page-header">
        <h1>AI Conversations</h1>
        <div className="page-filters">
          <select value={period} onChange={e => setPeriod(e.target.value)}>
            {PERIODS.map(p => <option key={p}>{p}</option>)}
          </select>
          <select value={region} onChange={e => setRegion(e.target.value)}>
            {REGIONS.map(r => <option key={r}>{r}</option>)}
          </select>
        </div>
      </header>

      <div className="conversations-full">
        <ConversationPanel
          period={period}
          region={region}
          threadId={threadId}
          messages={messages}
          isPending={isPending}
          onSend={send}
        />
      </div>
    </div>
  );
}
