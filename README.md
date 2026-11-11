# App Store Dashboard

A macOS desktop app and a website. It is not built for iOS, Android, Windows or Linux.

A Flutter dashboard for App Store Connect that signs in with an **API key only** (Issuer ID + Key ID + `.p8`), no Apple ID.
Runs as a macOS desktop app and as a website.

The sidebar has four places: **Apps**, **Sales & Trends**, **Signing** (certificates, identifiers, profiles, devices) and
**Users and Access**. Everything about one app lives inside that app: Store Listing, TestFlight & Groups, Customer Reviews,
Builds, Upload .IPA, In-App Purchases and App Review Preflight. There is no top-level TestFlight, and the .ipa upload is not
on the Apps list, because an .ipa belongs to one app.

Click the search box in the title bar, or press **⌘K** (**Ctrl K** on the web), for the command palette: jump to any app,
or run Upload New Build, Check Sales & Proceeds, Manage Team or Lock Console. The sun/moon button switches light and dark
mode (it follows the system until you press it; the choice is not saved).

## Clients (multiple keys)

Click the client card at the top of the sidebar to switch between saved keys, **Add client (key + issuer ID)**, rename,
set a vendor number, or remove one. Entering the same issuer + key again replaces the saved entry.

## Desktop (macOS)

```
flutter run -d macos
```

* Keys are stored in the system keychain.
* The app asks for **Touch ID or your account password** once, each time it is launched. Switching to another app does
  not lock it again; "Lock now" (sidebar, or ⌘K → Lock Console) locks it on demand.
* If the Mac has no password/Touch ID configured, the app refuses to open rather than store keys unprotected.
* Requests go straight to `api.appstoreconnect.apple.com`.

## Website

Apple's API sends no CORS headers, so a browser cannot call it directly. `server/server.js` (no dependencies) serves the
built site and forwards `/asc/*` to Apple, passing the `Authorization` header through. It logs and stores nothing.

```
flutter build web --release
node server/server.js                 # http://127.0.0.1:8080
PORT=9000 HOST=0.0.0.0 node server/server.js
node --test server/test/server.test.js # proxy tests
```

* The JWT is signed in the browser; the private key is never sent to the server, only the short-lived token is.
* In a browser the keys are held **in memory for the tab only** (nothing is persisted), and there is no device-lock
  prompt: `local_auth` has no web support. A passkey (WebAuthn) lock is the way to add one.
* Put the server behind HTTPS and access control before exposing it beyond your own machine.
* For `flutter run -d chrome`, point at a running proxy: `--dart-define=ASC_PROXY=http://127.0.0.1:8080/asc`.

## Sales & Trends

Needs your **vendor number** (App Store Connect → Payments and Financial Reports), which is not part of the API key. Set it from the
client menu. Days Apple hasn't published yet show as gaps.

## Changing your App Store Connect account (read this before using the write features)

These actions change the real account, and some cannot be undone, so each one asks for confirmation first:

* **Listing tab**: every locale's app name, subtitle, privacy URL, promotional text, description, keywords, what's new, URLs, and
  the screenshots. Edits (text, adding / removing / reordering screenshots, new device sizes) are **staged**, not sent. A bar
  shows the pending count; **Review changelist** shows every change (line diffs for long text, thumbnails for new
  screenshots), then **Apply** sends them. On a live version only the promotional text is editable; the rest unlocks on a
  version being prepared. Adding locales is not built. Screenshots use Apple's App Asset Library (an image is uploaded to the app's library, then placed on the locale
  per device group); the picture's pixel size is checked against Apple's list before anything is sent. Removing a screenshot
  only takes it off this version; the image stays in the library.
* **Submit tab**: a preflight checklist (version state, build attached and processed, export compliance, per-locale
  listing text and screenshots, App Review contact details, release option, unsent Listing changes) with a fix button for
  each item: *New version*, *Choose build*, export-compliance answer, review contact form, release option. **Submit for
  review** is only enabled when no check fails, re-checks against Apple first, and requires typing the version number. A
  submission that is waiting or in review can be cancelled. Age-rating answers, pricing and availability are not checked
  here: Apple can still ask for them.
* **Purchases tab**: *New in-app purchase* and *Bulk create* (paste or choose a CSV; columns `product_id`, `display_name`
  required, plus `reference_name`, `description`, `price`, `type`, `locale`, `review_note`, `family_sharable`). Each IAP is
  created, localized, priced (lowest Apple price point at or above your price, in the territory you pick) and made available.
  Product IDs can never be reused, even after deleting. Review screenshots and submission are not handled. Subscriptions are not created.
* **Upload tab** (desktop only): reads version and build from the `.ipa`, uploads it through Apple's build-upload API, and
  waits for processing. A processed build can never be deleted, only left to expire. The history list works on the web too.

The request shapes follow Apple's OpenAPI spec and are unit-tested (`flutter test`), and the IAP flow is ported from
`scripts/iap_update/create_iaps.js` in the Vidyagram repo. The create/save/upload calls themselves have not been run against
a real account, by design.

## Users and Access

**Invite user** emails an invitation (name, roles, all apps or chosen apps). Pending invitations can be revoked. A person's
roles and app access can be edited, and they can be removed from the team. The Account Holder cannot be edited or removed.
This needs an Admin or Account Holder key.

## TestFlight groups

Each app has a **TestFlight** tab: internal and external groups, with testers (add by email, remove), builds (add or remove
when the group does not get all builds automatically), the public link and its limit, tester feedback, and a **Submit for
beta review** button for builds an external group needs reviewed. Groups can be created and deleted. Internal testers must
already be users on the team.

## Apps list: one request

The Apps page makes **one** request (`GET /v1/apps?include=appStoreVersions…`) and works out each app's newest version,
platform and status from it. It loads no builds, icons or reviews per app, so it stays at one request however many apps
there are, and the command palette reuses the same result. The grid/list switch, search and filters (All, Ready for Sale,
In Review, Universal & macOS) all work on that data. "Universal & macOS" means any platform other than iOS, because one
request cannot tell a universal app from an iPhone one. Icons need a request per app, so apps show a coloured initial.

## Customer reviews

Rating breakdown (tap a star row to filter), filters (All, 1-3★ Needs Reply, Unanswered), search, and replies: pick a
template or write your own (up to 5,970 characters), confirm, and the reply is posted as the developer response. A reply can
be edited (it replaces the earlier one) or deleted. Replies are public.

## Other additions

* **TestFlight public link**: external groups with a link show a QR code and a **Copy Link** button.
* **Clone to Other Locales** (Store Listing): copy What's New and promotional text from one locale to others. It only stages
  edits in the changelist; nothing is sent until you apply it. On a live version only promotional text can be copied.
* **Export** (app header, and Sales & Trends): reviews, in-app purchases and sales reports as CSV or JSON through the save
  dialog. Text that starts with `=`, `+`, `-` or `@` gets a leading apostrophe in CSV so a spreadsheet cannot run it as a
  formula. Pricing is not included in the in-app purchase export.

The window has no native title bar: the app draws its own, and on macOS the traffic-light buttons sit over its left end.
