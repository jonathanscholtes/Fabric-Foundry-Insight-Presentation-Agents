import { useQuery } from '@tanstack/react-query';
import { api } from '../api';

export function useAnalytics(period, region) {
  return useQuery({
    queryKey: ['analytics', period, region],
    queryFn: () => api.get('/analytics', { params: { period, region } }).then(r => r.data),
    enabled: Boolean(period && region),
    staleTime: 5 * 60 * 1000,
  });
}
