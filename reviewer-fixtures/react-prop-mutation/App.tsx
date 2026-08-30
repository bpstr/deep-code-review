type Props = { items: string[] }

export function ItemList(props: Props) {
  props.items.push('rendered')
  return <ul>{props.items.map((item) => <li key={item}>{item}</li>)}</ul>
}
