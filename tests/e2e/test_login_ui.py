import os
import re

from playwright.sync_api import Page, expect


BASE_URL = os.getenv("BASE_URL", "http://127.0.0.1:4000")


def test_admin_login(page: Page):
    page.goto(f"{BASE_URL}/login")

    expect(page.get_by_text("Login to your account")).to_be_visible()

    page.locator('input[name="email"]').fill("admin@example.com")
    page.locator('input[name="password"]').fill("admin")

    page.get_by_role("button", name="Login").click()

    expect(page).to_have_url(re.compile(r".*/dashboard/.*"))
