# Setzo branding audit — September 29, 2026

## Published fixes

- **Legacy website links:** `https://zor0000.github.io/ironlog/` and `/ironlog/privacy.html` now return redirect pages pointing at their Setzo equivalents. Browser checks verified that query strings and fragments survive. The redirects live in [Zor0000.github.io](https://github.com/Zor0000/Zor0000.github.io), with a fallback for other `/ironlog/` page paths. GitHub Pages serves static redirects; these are HTML/JavaScript redirects, not HTTP 301s. The existing `github.com/Zor0000/ironlog` repository URL still returns its normal HTTP 301 to Setzo.
- **Website:** Added the rename notice, a public [support page](https://zor0000.github.io/setzo/support.html), canonical privacy URL, and sharing metadata using the existing Setzo app icon. Kept the dumbbell favicon unchanged. The live Pages homepage is generated from `README.md`; `website/` is the separate Next.js marketing source and received matching metadata and support/privacy links.
- **Supabase:** Verified the live project URL, current and legacy mobile callbacks, and sender display name. Branded all 13 authentication/security email templates and subjects. Confirmation links, token variables, SMTP settings, and notification enablement remain unchanged. No test emails were sent. The support and sender mailbox remains the existing working Gmail address.
- **Google consent screen:** Saved Setzo app icon, homepage, privacy URL, and `zor0000.github.io` as an authorized domain. App name was already Setzo. Support/developer contacts were already correct. Google displayed “Branding changes saved!” The project remains External / Testing, so production publishing and verification are a separate launch step. There was no old logo to replace; the logo field was empty.
- **Apple:** Read every available App Store version/localization. App Store 1.0 has one locale, en-US, and no uploaded screenshot sets or preview videos. Name and privacy URL already use Setzo. Added missing marketing/support URLs and TestFlight marketing URL. Added “IronLog is now Setzo” to the latest build's What to Test notes; existing workout/account continuity and IronFuel are explained there. Both beta groups have neutral names; no public TestFlight link is enabled.
- **Other public references:** Renamed IronLog to Setzo in the GitHub profile README and the project card at [neeraj.works](https://www.neeraj.works/), and updated the portfolio's GitHub link and obsolete PWA description. Verified the deployed portfolio contains Setzo and no IronLog reference.

## Preserved deliberately

IronFuel, the dumbbell favicon, Apple app/bundle identifiers, historical releases, local storage and keychain keys, legacy mobile links, and saved user data are unchanged. No iOS binary change was required for this follow-up.

## Verification and maintenance

- Website production build and TypeScript checks passed.
- Homepage, privacy, support, favicon, and sharing-image URLs returned HTTP 200.
- Live homepage contains Setzo `og:image`, `summary_large_image`, the existing favicon, and the rename notice.
- Apple audit and metadata update succeeded in [GitHub Actions](https://github.com/Zor0000/setzo/actions/runs/36518326584). Its artifact records actual store metadata, screenshots/previews, latest build notes, and group settings.
- Supabase Management API read-back matched all 27 changed branding fields. Source of truth: `supabase/email-branding.json`. Apply with `SUPABASE_ACCESS_TOKEN` available in the environment using `python3 scripts/sync_supabase_email_branding.py`; this patches branding fields only. Never commit the token.
- The Apple branding audit workflow can be dispatched again without building another binary. It refreshes editable metadata and latest TestFlight notes, then exports a report.

No product-specific social handles or QR/invite assets were linked in the inspected repository. New branded email addresses or domains require an actual mailbox/domain to be provisioned; do not substitute an address that cannot receive support requests.
