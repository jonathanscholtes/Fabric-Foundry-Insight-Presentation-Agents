import { NavLink, useNavigate } from 'react-router-dom'

// SVG icons — inline, 18x18
function IconPlusCircle() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10" />
      <line x1="12" y1="8" x2="12" y2="16" />
      <line x1="8" y1="12" x2="16" y2="12" />
    </svg>
  )
}

function IconMessageSquare() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    </svg>
  )
}

function IconFolder() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
    </svg>
  )
}

function IconFileText() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="16" y1="13" x2="8" y2="13" />
      <line x1="16" y1="17" x2="8" y2="17" />
      <polyline points="10 9 9 9 8 9" />
    </svg>
  )
}

function IconBarChart() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <line x1="18" y1="20" x2="18" y2="10" />
      <line x1="12" y1="20" x2="12" y2="4" />
      <line x1="6" y1="20" x2="6" y2="14" />
    </svg>
  )
}

function IconSettings() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  )
}

export default function Sidebar() {
  const navigate = useNavigate()

  function handleNewMbr() {
    navigate('/dashboard')
    // Dispatch a custom event so Dashboard can reset its state
    window.dispatchEvent(new CustomEvent('longhaul:reset'))
  }

  return (
    <aside className="sidebar">
      {/* Brand */}
      <div className="sidebar-logo">
        <img src="/longhaul-logo.svg" alt="LONGHAUL" />
        <div className="sidebar-logo-text">
          <span className="sidebar-logo-name">LONGHAUL</span>
          <span className="sidebar-logo-tagline">MBR AI Platform</span>
        </div>
      </div>

      {/* Nav */}
      <nav>
        <ul className="sidebar-nav">
          {/* New MBR — uses button-style click handler to reset state */}
          <li>
            <button
              className="sidebar-nav-item"
              style={{ width: '100%', background: 'none', border: 'none', cursor: 'pointer', borderLeft: '3px solid transparent' }}
              onClick={handleNewMbr}
            >
              <IconPlusCircle />
              + New MBR
            </button>
          </li>

          <li>
            <NavLink
              to="/conversations"
              className={({ isActive }) => `sidebar-nav-item${isActive ? ' active' : ''}`}
            >
              <IconMessageSquare />
              Conversations
            </NavLink>
          </li>

          <li>
            <NavLink
              to="/library"
              className={({ isActive }) => `sidebar-nav-item${isActive ? ' active' : ''}`}
            >
              <IconFolder />
              MBR Library
            </NavLink>
          </li>

          <li>
            <NavLink
              to="/presentations"
              className={({ isActive }) => `sidebar-nav-item${isActive ? ' active' : ''}`}
            >
              <IconFileText />
              Presentations
            </NavLink>
          </li>

          <li><hr /></li>

          <li>
            <NavLink
              to="/reports"
              className={({ isActive }) => `sidebar-nav-item${isActive ? ' active' : ''}`}
            >
              <IconBarChart />
              Client &amp; Reports
            </NavLink>
          </li>

          <li><hr /></li>

          <li>
            <NavLink
              to="/settings"
              className={({ isActive }) => `sidebar-nav-item${isActive ? ' active' : ''}`}
            >
              <IconSettings />
              Settings
            </NavLink>
          </li>
        </ul>
      </nav>

      {/* User footer */}
      <div className="sidebar-user">
        <div className="sidebar-avatar">JS</div>
        <div className="sidebar-user-info">
          <span className="sidebar-user-name">Jonathan Scholtes</span>
          <span className="sidebar-user-role">Fleet Analyst</span>
        </div>
      </div>
    </aside>
  )
}
