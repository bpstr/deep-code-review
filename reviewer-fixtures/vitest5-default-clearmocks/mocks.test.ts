import { expect, test, vi } from 'vitest'

const fn = vi.fn()

test('first call', () => {
  fn()
  expect(fn).toHaveBeenCalledTimes(1)
})

test('history is cleared by Vitest 5 default', () => {
  fn()
  expect(fn).toHaveBeenCalledTimes(1)
})
