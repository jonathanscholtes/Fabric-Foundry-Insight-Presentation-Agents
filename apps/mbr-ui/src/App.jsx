import { useState } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import Sidebar from './components/layout/Sidebar.jsx'
import TopBar from './components/layout/TopBar.jsx'
import Dashboard from './pages/Dashboard.jsx'
import MbrLibrary from './pages/MbrLibrary.jsx'

function ComingSoon({ title }) {
  return (
    <div className="page-container">
      <header className="page-header">
        <h1>{title}</h1>
      </header>
      <div className="empty-state">Coming soon.</div>
    </div>
  )
}

export default function App() {
  const [period, setPeriod] = useState('May 2025')
  const [region, setRegion] = useState('North')

  return (
    <div className="app-shell">
      <Sidebar />
      <TopBar period={period} region={region} onPeriod={setPeriod} onRegion={setRegion} />
      <main className="content">
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<Dashboard period={period} region={region} />} />
          <Route path="/presentations" element={<MbrLibrary />} />
          <Route path="/settings"     element={<ComingSoon title="Settings" />} />
          <Route path="/reports"      element={<ComingSoon title="Data & Reports" />} />
          <Route path="/alerts"       element={<ComingSoon title="Alerts" />} />
          <Route path="/help"         element={<ComingSoon title="Help" />} />
        </Routes>
      </main>
    </div>
  )
}
