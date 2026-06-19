import { NavLink } from 'react-router-dom'

function Icon({ d, size = 15 }) {
  return (
    <svg
      width={size} height={size} viewBox="0 0 24 24"
      fill="none" stroke="currentColor" strokeWidth="1.8"
      strokeLinecap="round" strokeLinejoin="round"
    >
      {(Array.isArray(d) ? d : [d]).map((path, i) => (
        <path key={i} d={path} />
      ))}
    </svg>
  )
}

const MAIN_NAV = [
  {
    label: 'Overview',
    to: '/dashboard',
    icon: ['M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z', 'M9 22V12h6v10'],
  },
  {
    label: 'Presentations',
    to: '/presentations',
    icon: ['M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z', 'M14 2v6h6', 'M16 13H8', 'M16 17H8'],
  },
  {
    label: 'Data & Reports',
    to: '/reports',
    icon: ['M18 20V10', 'M12 20V4', 'M6 20v-6'],
  },
  {
    label: 'Alerts',
    to: '/alerts',
    badge: 7,
    icon: ['M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9', 'M13.73 21a2 2 0 01-3.46 0'],
  },
]

const FLEET_NAV = [
  {
    label: 'Fleet Summary',
    icon: ['M12 2L2 7l10 5 10-5-10-5z', 'M2 17l10 5 10-5', 'M2 12l10 5 10-5'],
  },
  {
    label: 'Equipment',
    icon: ['M1 3h15v13H1z', 'M16 8h4l3 3v5h-7V8z', 'M5.5 21a2.5 2.5 0 100-5 2.5 2.5 0 000 5z', 'M18.5 21a2.5 2.5 0 100-5 2.5 2.5 0 000 5z'],
  },
  {
    label: 'Drivers',
    icon: ['M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2', 'M9 11a4 4 0 100-8 4 4 0 000 8z', 'M23 21v-2a4 4 0 00-3-3.87', 'M16 3.13a4 4 0 010 7.75'],
  },
  {
    label: 'Customers',
    icon: ['M20 7H4a2 2 0 00-2 2v10a2 2 0 002 2h16a2 2 0 002-2V9a2 2 0 00-2-2z', 'M16 3H8a2 2 0 00-2 2v2h12V5a2 2 0 00-2-2z'],
  },
  {
    label: 'Lanes',
    icon: ['M3 12h18', 'M3 6h18', 'M3 18h18'],
  },
]

export default function Sidebar() {
  return (
    <aside className="sidebar">
      {/* Brand */}
      <div className="sidebar-logo">
        <img src="/trucking_logo.png" alt="LONGHAUL INSIGHTS" />
      </div>

      {/* Main nav + Fleet Context */}
      <nav className="sidebar-nav-wrap">
        <ul className="sidebar-nav">
          {MAIN_NAV.map(item => (
            <li key={item.label}>
              <NavLink
                to={item.to}
                className={({ isActive }) => `sidebar-nav-item${isActive ? ' active' : ''}`}
              >
                <Icon d={item.icon} />
                {item.label}
                {item.badge && <span className="sidebar-nav-badge">{item.badge}</span>}
              </NavLink>
            </li>
          ))}

          <li aria-hidden><hr /></li>
          <li><div className="sidebar-section-label">Fleet Context</div></li>

          {FLEET_NAV.map(item => (
            <li key={item.label}>
              <span className="sidebar-nav-item sidebar-nav-item--sub">
                <Icon d={item.icon} size={13} />
                {item.label}
              </span>
            </li>
          ))}
        </ul>
      </nav>

      {/* Bottom: user + settings + help */}
      <div className="sidebar-bottom">
        <div className="sidebar-user">
          <div className="sidebar-avatar">JS</div>
          <div className="sidebar-user-info">
            <span className="sidebar-user-name">Jonathan Scholtes</span>
            <span className="sidebar-user-role">Fleet Analyst</span>
          </div>
          <Icon d="M18 15l-6-6-6 6" size={12} />
        </div>
        <NavLink
          to="/settings"
          className={({ isActive }) => `sidebar-bottom-link${isActive ? ' active' : ''}`}
        >
          <Icon d={['M12 15a3 3 0 100-6 3 3 0 000 6z', 'M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z']} size={14} />
          Settings
        </NavLink>
        <NavLink
          to="/help"
          className={({ isActive }) => `sidebar-bottom-link${isActive ? ' active' : ''}`}
        >
          <Icon d={['M9.09 9a3 3 0 015.83 1c0 2-3 3-3 3', 'M12 17h.01']} size={14} />
          Help
        </NavLink>
      </div>
    </aside>
  )
}
