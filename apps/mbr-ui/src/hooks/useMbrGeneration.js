import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '../api';

function triggerDownload(url, filename) {
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

export function useMbrGeneration(period, region) {
  const qc = useQueryClient();

  const filename = `MBR-${region ?? 'All'}-${(period ?? '').replace(' ', '')}.pptx`;

  const templateSlidesQuery = useQuery({
    queryKey: ['template-slides'],
    queryFn: () => api.get('/templates/default/slides'),
    staleTime: 30 * 60 * 1000,
  });

  const generateMutation = useMutation({
    mutationFn: () => api.post('/presentations', { period, region }),
    onSuccess: (data) => {
      qc.invalidateQueries({ queryKey: ['mbr-library'] });
      if (data?.deck_url) {
        triggerDownload(data.deck_url, filename);
      }
    },
  });

  const downloadAgainMutation = useMutation({
    mutationFn: (deck_id) => api.get(`/presentations/${deck_id}/download`),
    onSuccess: (data) => {
      if (data?.url) {
        triggerDownload(data.url, filename);
      }
    },
  });

  return { templateSlidesQuery, generateMutation, downloadAgainMutation };
}
