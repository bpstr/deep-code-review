import { test, expect } from '@playwright/test'

test('dashboard loads', async ({ page }) => {
  await page.goto('/dashboard')
  await page.waitForTimeout(3000)
  await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
})
