---
name: nextjs-optimization-pro
description: "Performance optimization specialist for Next.js 15.1.x applications. Focused on Server Components, rendering strategies, and structuring Client/Server boundaries, with specific guidelines on using img tags."
source: community
---

# Next.js 15.1.x Performance Optimization Guide

## Purpose

This skill aims to guide development and refactoring sessions to ensure Next.js 15.1.x applications are built with maximum performance. The skill focuses on modern optimization best practices introduced in Next.js 15, with a strong emphasis on carefully distinguishing between server and client rendering to achieve the best Web Vitals metrics and end-user experience.

## Critical Rules (Mandatory)

### Image Usage (Maximum Attention)

* **FORBIDDEN:** The use of the dynamic `<Image />` component imported from `next/image` is strictly forbidden under this guideline.
* **MANDATORY:** Always use the standard HTML `<img>` tag.
* **Reason:** Image optimization strategies, in specific scenarios, should be delegated to external CDNs or a pipeline outside the runtime cost of the Next.js server. Native image processing can burden the workers.
* **Action/Audit:** When reviewing code, if `import Image from "next/image"` exists, you MUST remove the import and refactor any `<Image />` to the respective common `<img>` tag, ensuring appropriate attributes like `loading="lazy"` (when images are below the fold) and explicit dimensions to prevent Cumulative Layout Shift (CLS).

## 1. Server-Side Rendering (SSR) and React Server Components (RSC)

By default, the App Router (v15.1) adopts Server Components first. Optimization through server-side rendering drastically reduces client load and the payload of downloaded bundles.

* **Data Fetching Colocation:** Always execute heavy business rules and API or database queries directly in Server Components (which operate under NodeJS/Edge) rather than on the client side (like `useEffect` + client fetch). This decreases client-server round trips and the size of delivered JavaScript.
* **Streaming and Partial Prerendering (PPR):** Next.js 15 matures the use of Partial Prerendering. When utilizing this architecture, wrap asynchronous data-dependent components in a `React.Suspense` Boundary (`<Suspense fallback={<Skeleton />}>`). This quickly sends the layout shell (static skeleton) to the client and gradually streams the dynamic part to immensely optimize LCP and TTFB.
* **Avoid Waterfalls:** When multiple server requests (Promises) are executed simultaneously in the same Server Component, ensure the use of `Promise.all` instead of declaring multiple sequential `await`s if one does not depend on the result of the other.
* **Granularity of Dynamism:** Functions like `cookies()`, `headers()`, and `searchParams` variables force the entire route into dynamic rendering. Try to group the use of dynamic functions at the lowest possible level contained within Suspenses to avoid deactivating global static generation.

## 2. `use client` Optimization (Client Components)

Client Components inject interactivity into the front-end but come with the imminent cost of increasing the JavaScript Main Thread weight, strongly impacting relative metrics (Input Delay, INP).

* **Leaves of the Tree:** Keep `use client` only at the terminal leaves of the UI interactivity tree (buttons, small forms, toggles). One of the worst practices in Next.js is declaring `'use client'` at the top level of the main page and accidentally transforming the entire subsequent component tree into client-rendering.
* **Server Components injected as Children:** A Client Component can indeed embrace Server Components, provided they are passed purely via `children` props in the composition. With this, child nodes do not magically become clients, preventing massive bundles.
* **RSC Payload Minimization (Optimized Props):** When passing information from a Server Component to a Client Component via Prop, never send unnecessarily fat nested objects (e.g., the complete record of a DB table). Extract only the truly essential variables (`Title`, `ID`, `Status`) on the client. Unprocessed payload leaks unnecessary serialization traffic.
* **Costly Interactions and Third-Party Imports:** Break free from ties, avoid loading heavy packages like `luxon`, `moment`, or huge utility libs exclusively on the client. Refactor these conversions and logs preferably to the Server.

## 3. Bundle, Code Splitting, and Static Resources

* **Dynamic Imports (`next/dynamic`):** Mandatory module for huge UI elements that will **not** be immediately visible without user action (Complex Modals, Drawers, Heavy Data Visualization Charts). Use lazy load/dynamic imports aiming to postpone the First Load JS size.
* **Third-Party Scripts (`next/script`):** When importing trackers or Ad snippets, explicitly use the `<Script />` component. Leverage loading property strategies like `strategy="worker"` or `strategy="lazyOnload"` to avoid blocking the critical client parser.
* **Native Font Optimization:** Work with `next/font/google` or `next/font/local` during the inclusion of typographic fonts. Its engine pre-compiles the call and self-hosts preventing reflow and severe visual oscillation, eliminating FOUT/FOIT.
* **Intentional Caches:** Check for opportunities to use functions like `unstable_cache()` in Next 15 to temporarily store very expensive computations that serve multiple sequential requests.

## Quick Audit Cheat Sheet

1. Is there any import containing `"next/image"`? **[Remove immediately for a common `<img>` tag]**
2. Are there massive packages or very large `'use client'` declarations encompassing non-interactive root pages? **[Move to Leaves and isolate interactions]**
3. Is there a severely blocked screen load due to fetching the entire database JSON at once? **[Redesign employing `<Suspense>` and partial requests]**
4. Is the data sent from Server Components to Clients purified via a Data Transfer and devoid of huge superfluous data? **[Reduce the object exposed in Props]**
