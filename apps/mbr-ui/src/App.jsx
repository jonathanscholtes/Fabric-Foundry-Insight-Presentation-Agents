import { Routes, Route, Navigate } from 'react-router-dom'
import Sidebar from './components/layout/Sidebar.jsx'
import Dashboard from './pages/Dashboard.jsx'
import Conversations from './pages/Conversations.jsx'
import MbrLibrary from './pages/MbrLibrary.jsx'

function SettingsPlaceholder() {
  return (
    <div className="page-container">
      <h2>Settings</h2>
      <p className="muted">Settings configuration coming soon.</p>
    </div>
  )
}

export default function App() {
  return (
    <div className="app-shell">
      <Sidebar />
      <main className="content">
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/conversations" element={<Conversations />} />
          <Route path="/library" element={<MbrLibrary />} />
          <Route path="/presentations" element={<MbrLibrary />} />
          <Route path="/settings" element={<SettingsPlaceholder />} />
          <Route path="/reports" element={<SettingsPlaceholder />} />
        </Routes>
      </main>
    </div>
  )
}
