import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '../api';

export function useMbrGeneration(period, region) {
  const qc = useQueryClient();

  const templateSlidesQuery = useQuery({
    queryKey: ['template-slides', period, region],
    queryFn: () =>
      api.get('/presentations/templates', { params: { period, region } }).then(r => r.data),
    enabled: Boolean(period && region),
    staleTime: 10 * 60 * 1000,
  });

  const generateMutation = useMutation({
    mutationFn: () =>
      api.post('/presentations/generate', { period, region }).then(r => r.data),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['mbr-library'] });
    },
  });

  return { templateSlidesQuery, generateMutation };
}
