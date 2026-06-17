import { useMbrGeneration } from '../hooks/useMbrGeneration';

export default function PresentationPanel({ period, region }) {
  const { templateSlidesQuery, generateMutation } = useMbrGeneration(period, region);

  const { data: slides, isLoading: slidesLoading } = templateSlidesQuery;
  const { mutate: generate, isPending: generating, data: genResult, isError: genError } = generateMutation;

  function handleGenerate() {
    generate();
  }

  return (
    <div className="presentation-panel">
      <div className="presentation-panel-header">
        <h3>MBR Presentation</h3>
        <button
          className="btn btn--primary"
          onClick={handleGenerate}
          disabled={generating || !period || !region}
        >
          {generating ? 'Generating…' : 'Generate MBR'}
        </button>
      </div>

      {genError && (
        <div className="presentation-error">
          Generation failed. Please try again.
        </div>
      )}

      {genResult?.deck_url && (
        <div className="presentation-success">
          <a href={genResult.deck_url} target="_blank" rel="noreferrer" className="btn btn--secondary">
            Download Deck
          </a>
        </div>
      )}

      <div className="template-slides">
        {slidesLoading && <div className="template-slides--loading">Loading template…</div>}
        {slides?.slides?.map((slide, i) => (
          <div key={i} className="template-slide">
            <img
              src={slide.thumbnail_url}
              alt={`Slide ${i + 1}: ${slide.title}`}
              loading="lazy"
            />
            <span className="template-slide-label">Slide {i + 1}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
