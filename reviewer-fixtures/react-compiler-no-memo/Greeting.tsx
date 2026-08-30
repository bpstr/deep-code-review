type Props = { first: string; last: string }

export function Greeting({ first, last }: Props) {
  const fullName = `${first} ${last}`
  return <p>Hello {fullName}</p>
}
