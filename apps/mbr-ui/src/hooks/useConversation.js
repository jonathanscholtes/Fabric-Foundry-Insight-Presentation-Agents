import { useState, useCallback } from 'react';
import { useMutation } from '@tanstack/react-query';
import { api } from '../api';

export function useConversation(period, region) {
  const [threadId] = useState(() => crypto.randomUUID());
  const [messages, setMessages] = useState([]);

  const mutation = useMutation({
    mutationFn: (content) =>
      api.post('/conversations', { thread_id: threadId, period, region, content })
        .then(r => r.data),
    onMutate: (content) => {
      setMessages(prev => [...prev, { role: 'user', content }]);
    },
    onSuccess: (data) => {
      setMessages(prev => [...prev, { role: 'assistant', content: data.content }]);
    },
  });

  const send = useCallback((content) => {
    mutation.mutate(content);
  }, [mutation]);

  return { threadId, messages, isPending: mutation.isPending, send };
}
