import { useRef, useEffect, useState } from 'react';

export default function ConversationPanel({ period, region, threadId, messages, isPending, onSend }) {
  const [input, setInput] = useState('');
  const bottomRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isPending]);

  function handleSubmit(e) {
    e.preventDefault();
    const text = input.trim();
    if (!text || isPending) return;
    setInput('');
    onSend(text);
  }

  return (
    <div className="conversation-panel">
      <div className="conversation-messages">
        {messages.length === 0 && !isPending && (
          <div className="conversation-empty">
            Ask a question about {region} — {period} performance.
          </div>
        )}
        {messages.map((msg, i) => (
          <div key={i} className={`message message--${msg.role}`}>
            <span className="message-role">{msg.role === 'user' ? 'You' : 'Agent'}</span>
            <span className="message-content">{msg.content}</span>
          </div>
        ))}
        {isPending && (
          <div className="message message--assistant message--pending">
            <span className="message-role">Agent</span>
            <span className="message-content typing-indicator">
              <span /><span /><span />
            </span>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      <form className="conversation-input" onSubmit={handleSubmit}>
        <input
          type="text"
          value={input}
          onChange={e => setInput(e.target.value)}
          placeholder="Ask about KPIs, costs, drivers…"
          disabled={isPending || !period || !region}
        />
        <button type="submit" disabled={isPending || !input.trim() || !period || !region}>
          Send
        </button>
      </form>
    </div>
  );
}
