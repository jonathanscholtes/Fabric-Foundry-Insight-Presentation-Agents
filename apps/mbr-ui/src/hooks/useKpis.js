import { useQuery } from '@tanstack/react-query';
import { api } from '../api';

export function useKpis(period, region) {
  return useQuery({
    queryKey: ['kpis', period, region],
    queryFn: () => api.get('/kpis', { params: { period, region } }),
    enabled: Boolean(period && region),
    staleTime: 5 * 60 * 1000,
  });
}
