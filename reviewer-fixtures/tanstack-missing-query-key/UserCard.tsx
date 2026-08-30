import { useQuery } from '@tanstack/react-query'

export function UserCard({ userId }: { userId: string }) {
  const query = useQuery({
    queryKey: ['user'],
    queryFn: () => fetch(`/api/users/${userId}`).then((response) => response.json()),
  })

  return <div>{query.data?.name}</div>
}
