export const config = {
  userName:    'Jonathan Scholtes',
  userRole:    'Fleet Analyst',
  appName:     'LONGHAUL',
  apiBase:     '/api',
};

export function currentMonthPeriod() {
  const d = new Date();
  return `${d.toLocaleString('default', { month: 'long' })}${d.getFullYear()}`;
  // e.g. "May2025"
}
