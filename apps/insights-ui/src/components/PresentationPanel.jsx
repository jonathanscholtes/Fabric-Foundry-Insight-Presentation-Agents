import { useEffect, useState } from 'react'
import { usePresentationGeneration } from '../hooks/usePresentationGeneration'

function IconCheck() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="20 6 9 17 4 12" />
    </svg>
  )
}

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

// Phases mirror the real backend pipeline; `at` is the elapsed second the step
// becomes active. Timings are tuned to the typical 30–60s run — they are an
// estimate, not server-reported progress.
const GENERATION_STEPS = [
  { label: 'Connecting to Azure AI Foundry', at: 0 },
  { label: 'Querying Fabric Lakehouse for KPIs', at: 4 },
  { label: 'Analyzing trends & composing insights', at: 13 },
  { label: 'Building charts & assembling slides', at: 27 },
  { label: 'Rendering preview & finalizing', at: 42 },
]

export default function PresentationPanel({ period, region }) {
  const { existingDeckQuery, generateMutation, downloadAgainMutation, activeDeckId } = usePresentationGeneration(period, region)
  const {
    mutate: generate,
    isPending: generating,
    data: genResult,
    isError: genError,
  } = generateMutation
  const { mutate: downloadAgain, isPending: downloading } = downloadAgainMutation

  // Drive the staged progress indicator off elapsed wall-clock time.
  const [elapsed, setElapsed] = useState(0)
  useEffect(() => {
    if (!generating) { setElapsed(0); return }
    const start = Date.now()
    const id = setInterval(() => setElapsed((Date.now() - start) / 1000), 200)
    return () => clearInterval(id)
  }, [generating])

  // Ease toward 95% so the bar always moves but never "completes" before the
  // request resolves; success state snaps it away.
  const progress = Math.min(95, 95 * (1 - Math.exp(-elapsed / 15)))
  const activeStep = GENERATION_STEPS.reduce((acc, s, i) => (elapsed >= s.at ? i : acc), 0)
  const mm = Math.floor(elapsed / 60)
  const ss = String(Math.floor(elapsed % 60)).padStart(2, '0')

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

      {generating && (
        <div className="generation-progress" role="status" aria-live="polite">
          <div className="gen-progress-header">
            <span>Generating presentation…</span>
            <span className="gen-progress-timer">{mm}:{ss}</span>
          </div>
          <div className="gen-progress-bar">
            <div className="gen-progress-bar-fill" style={{ width: `${progress}%` }} />
          </div>
          <ul className="gen-steps">
            {GENERATION_STEPS.map((s, i) => {
              const state = i < activeStep ? 'done' : i === activeStep ? 'active' : 'pending'
              return (
                <li key={i} className={`gen-step gen-step--${state}`}>
                  <span className="gen-step-icon">
                    {state === 'done' ? <IconCheck /> : state === 'active' ? <span className="spinner" /> : null}
                  </span>
                  {s.label}
                </li>
              )
            })}
          </ul>
          <div className="gen-progress-hint">This usually takes 30–60 seconds. Please keep this tab open.</div>
        </div>
      )}
      {genError && !generating && (
        <div className="presentation-error">Generation failed — please try again.</div>
      )}
      {genResult && !genError && !generating && (
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
          disabled={!activeDeckId || downloading}
          onClick={() => activeDeckId && downloadAgain(activeDeckId)}
        >
          {downloading
            ? <><span className="spinner" /> Downloading…</>
            : <><IconDownload /> Download Again</>}
        </button>
      </div>
    </div>
  )
}
