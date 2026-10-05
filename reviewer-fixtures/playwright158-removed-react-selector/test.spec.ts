import { test } from "@playwright/test";
test("legacy selector", async ({ page }) => { await page.locator("_react=Button").click(); });
