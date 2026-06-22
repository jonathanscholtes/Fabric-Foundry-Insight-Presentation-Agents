import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '../api';

function triggerDownload(url, filename) {
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

function formatGeneratedAt(value) {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString('en-US', {
    year: 'numeric', month: 'short', day: 'numeric',
    hour: 'numeric', minute: '2-digit',
  });
}

function DeckCard({ deck }) {
  const [downloading, setDownloading] = useState(false);

  async function handleDownload() {
    setDownloading(true);
    try {
      const data = await api.get(`/presentations/${deck.deck_id}/download`);
      if (data?.url) {
        const filename = `MBR-${deck.region}-${(deck.period ?? '').replace(' ', '')}.pptx`;
        triggerDownload(data.url, filename);
      }
    } catch (err) {
      console.error('Download failed:', err);
    } finally {
      setDownloading(false);
    }
  }

  return (
    <div className="deck-card">
      <div className="deck-card-meta">
        <div className="deck-card-titlerow">
          <span className="deck-card-title">{deck.region} — {deck.period}</span>
          <span className="deck-card-id" title={`Deck ID ${deck.deck_id}`}>{deck.deck_id}</span>
        </div>
        <span className="deck-card-date">Generated {formatGeneratedAt(deck.generated_at)}</span>
      </div>
      <div className="deck-card-actions">
        <button
          className="btn btn--secondary btn--sm"
          onClick={handleDownload}
          disabled={downloading}
        >
          {downloading ? 'Downloading…' : 'Download'}
        </button>
      </div>
    </div>
  );
}

export default function PresentationsLibrary() {
  const [search, setSearch] = useState('');

  const { data, isLoading, isError } = useQuery({
    queryKey: ['presentations-library'],
    queryFn: () => api.get('/presentations'),
    staleTime: 2 * 60 * 1000,
  });

  // Collapse repeated generations: keep only the most recent deck per region+period.
  const latestByRegionPeriod = [...(data?.items ?? [])]
    .sort((a, b) => String(b.generated_at ?? '').localeCompare(String(a.generated_at ?? '')))
    .reduce((acc, deck) => {
      const key = `${deck.region ?? ''}|${deck.period ?? ''}`;
      if (!acc.seen.has(key)) {
        acc.seen.add(key);
        acc.items.push(deck);
      }
      return acc;
    }, { seen: new Set(), items: [] })
    .items;

  const decks = latestByRegionPeriod.filter(d => {
    if (!search) return true;
    const q = search.toLowerCase();
    return (d.region ?? '').toLowerCase().includes(q)
      || (d.period ?? '').toLowerCase().includes(q);
  });

  return (
    <div className="page-container">
      <header className="page-header">
        <div className="page-header-titles">
          <h1>Presentations</h1>
          {!isLoading && !isError && (
            <span className="page-header-subtitle">
              {decks.length} {decks.length === 1 ? 'presentation' : 'presentations'}
            </span>
          )}
        </div>
        <input
          type="search"
          placeholder="Search by region or period…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="library-search"
        />
      </header>

      {isLoading && <div className="loading-state">Loading presentations…</div>}
      {isError   && <div className="error-state">Failed to load library.</div>}

      {!isLoading && !isError && decks.length === 0 && (
        <div className="empty-state">No presentations found. Generate one from the Dashboard.</div>
      )}

      <div className="deck-grid">
        {decks.map(deck => <DeckCard key={deck.deck_id} deck={deck} />)}
      </div>
    </div>
  );
}
