import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '../api';

function DeckCard({ deck }) {
  return (
    <div className="deck-card">
      <div className="deck-card-thumb">
        {deck.thumbnail_url
          ? <img src={deck.thumbnail_url} alt={deck.title} loading="lazy" />
          : <div className="deck-card-thumb-placeholder" />
        }
      </div>
      <div className="deck-card-meta">
        <span className="deck-card-title">{deck.title ?? `${deck.region} — ${deck.period}`}</span>
        <span className="deck-card-date">{deck.created_at ? new Date(deck.created_at).toLocaleDateString() : ''}</span>
      </div>
      <div className="deck-card-actions">
        <a href={deck.deck_url} target="_blank" rel="noreferrer" className="btn btn--secondary btn--sm">
          Download
        </a>
      </div>
    </div>
  );
}

export default function MbrLibrary() {
  const [search, setSearch] = useState('');

  const { data, isLoading, isError } = useQuery({
    queryKey: ['mbr-library'],
    queryFn: () => api.get('/presentations/library').then(r => r),
    staleTime: 2 * 60 * 1000,
  });

  const decks = (data?.decks ?? []).filter(d => {
    if (!search) return true;
    const q = search.toLowerCase();
    return (d.title ?? '').toLowerCase().includes(q)
      || (d.region ?? '').toLowerCase().includes(q)
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
