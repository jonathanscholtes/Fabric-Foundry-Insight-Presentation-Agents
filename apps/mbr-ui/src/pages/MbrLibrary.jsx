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
        <span className="deck-card-title">{deck.region} — {deck.period}</span>
        <span className="deck-card-date">
          {deck.generated_at ? new Date(deck.generated_at).toLocaleDateString() : ''}
        </span>
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

export default function MbrLibrary() {
  const [search, setSearch] = useState('');

  const { data, isLoading, isError } = useQuery({
    queryKey: ['mbr-library'],
    queryFn: () => api.get('/presentations'),
    staleTime: 2 * 60 * 1000,
  });

  const decks = (data?.items ?? []).filter(d => {
    if (!search) return true;
    const q = search.toLowerCase();
    return (d.region ?? '').toLowerCase().includes(q)
      || (d.period ?? '').toLowerCase().includes(q);
  });

  return (
    <div className="page-container">
      <header className="page-header">
        <h1>MBR Library</h1>
        <input
          type="search"
          placeholder="Search decks…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="library-search"
        />
      </header>

      {isLoading && <div className="loading-state">Loading decks…</div>}
      {isError   && <div className="error-state">Failed to load library.</div>}

      {!isLoading && !isError && decks.length === 0 && (
        <div className="empty-state">No MBR decks found. Generate one from the Dashboard.</div>
      )}

      <div className="deck-grid">
        {decks.map(deck => <DeckCard key={deck.deck_id} deck={deck} />)}
      </div>
    </div>
  );
}
