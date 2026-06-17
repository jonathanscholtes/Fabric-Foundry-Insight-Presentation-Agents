import { PieChart, Pie, Cell } from 'recharts';

export default function EfficiencyDonut({ value }) {
  if (value == null) {
    return <div className="empty-state">—</div>;
  }

  const data = [{ value }, { value: 100 - value }];

  return (
    <div style={{ position: 'relative', display: 'inline-block', width: 140, height: 140 }}>
      <PieChart width={140} height={140}>
        <Pie
          data={data}
          cx={65}
          cy={65}
          innerRadius={45}
          outerRadius={60}
          startAngle={90}
          endAngle={-270}
          dataKey="value"
          strokeWidth={0}
        >
          <Cell fill="var(--color-brand-accent)" />
          <Cell fill="var(--color-border)" />
        </Pie>
      </PieChart>
      <div style={{
        position: 'absolute',
        top: '50%', left: '50%',
        transform: 'translate(-50%, -50%)',
        fontSize: 18, fontWeight: 600,
        color: 'var(--color-text-primary)',
      }}>
        {value.toFixed(1)}%
      </div>
    </div>
  );
}
