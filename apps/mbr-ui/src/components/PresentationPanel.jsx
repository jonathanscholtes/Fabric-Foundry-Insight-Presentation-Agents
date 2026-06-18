import { useMbrGeneration } from '../hooks/useMbrGeneration'

function IconDownload() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4" />
      <polyline points="7 10 12 15 17 10" />
      <line x1="12" y1="15" x2="12" y2="3" />
    </svg>
  )
}

function IconFileText() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="16" y1="13" x2="8" y2="13" />
      <line x1="16" y1="17" x2="8" y2="17" />
    </svg>
  )
}

const SLIDE_TITLES = [
  'Executive Summary',
  'Revenue Performance',
  'Cost Analysis',
  'Fleet Efficiency',
  'Regional Performance',
  'Outlook & Actions',
]

export default function PresentationPanel({ period, region }) {
  const { templateSlidesQuery, generateMutation, downloadAgainMutation } = useMbrGeneration(period, region)
  const { isLoading: slidesLoading } = templateSlidesQuery
  const {
    mutate: generate,
    isPending: generating,
    data: genResult,
    isError: genError,
  } = generateMutation
  const { mutate: downloadAgain, isPending: downloading } = downloadAgainMutation

  return (
    <div className="presentation-panel">

      {/* Deck cover thumbnail */}
      <div className="slide-thumbnail-wrap">
        <img src="/trucking_photo.png" alt="" className="slide-thumbnail-photo" />
        <div className="slide-thumbnail-overlay" />
        <div className="slide-thumbnail-text">
          <div className="slide-thumbnail-title">Management Business Review</div>
          <div className="slide-thumbnail-period">{period}</div>
        </div>
      </div>

      {/* Slide list */}
      <div className="slide-deck-label">Presentation Slide Deck</div>
      <ul className="slide-list">
        {SLIDE_TITLES.map((title, i) => (
          <li key={i} className="slide-list-item">
            <span className="slide-dot" />
            {title}
          </li>
        ))}
      </ul>

      {slidesLoading && (
        <div className="template-slides--loading">Loading template…</div>
      )}

      {genError && (
        <div className="presentation-error">Generation failed — please try again.</div>
      )}
      {genResult && !genError && (
        <div className="presentation-success">
          Deck ready — download started automatically.
        </div>
      )}

      {/* Actions */}
      <div className="presentation-actions">
        <button
          className="btn btn-primary"
          style={{ width: '100%' }}
          onClick={() => generate()}
          disabled={generating || !period || !region}
        >
          {generating
            ? <><span className="spinner" style={{ borderTopColor: '#000' }} /> Generating…</>
            : <><IconFileText /> Generate Presentation</>}
        </button>

        <button
          className="btn btn-outline"
          style={{ width: '100%' }}
          disabled={!genResult?.deck_id || downloading}
          onClick={() => genResult?.deck_id && downloadAgain(genResult.deck_id)}
        >
          {downloading
            ? <><span className="spinner" /> Downloading…</>
            : <><IconDownload /> Download Again</>}
        </button>
      </div>
    </div>
  )
}
