import { test } from "@playwright/test";
test("version-gated legacy selector", async ({ page }) => { await page.locator("_react=Button").click(); });
