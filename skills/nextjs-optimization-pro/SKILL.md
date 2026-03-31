---
name: nextjs-optimization-pro
description: "Performance optimization specialist for Next.js 16.2.x applications. Focused on Server Components, rendering strategies, and structuring Client/Server boundaries, with specific guidelines on using img tags."
source: ValarMindSkills
---

# Next.js 16.2.x Performance Optimization Guide

## Purpose

This skill aims to guide development and refactoring sessions to ensure Next.js 16.2.x applications are built with maximum performance. The skill focuses on modern optimization best practices introduced in Next.js 16, with a strong emphasis on carefully distinguishing between server and client rendering to achieve the best Web Vitals metrics and end-user experience.

## Critical Rules (Mandatory)

### Image Usage (Maximum Attention)

* **FORBIDDEN:** The use of the dynamic `<Image />` component imported from `next/image` is strictly forbidden under this guideline.
* **MANDATORY:** Always use the standard HTML `<img>` tag.
* **Reason:** Image optimization strategies, in specific scenarios, should be delegated to external CDNs or a pipeline outside the runtime cost of the Next.js server. Native image processing can burden the workers.
* **Action/Audit:** When reviewing code, if `import Image from "next/image"` exists, you MUST remove the import and refactor any `<Image />` to the respective common `<img>` tag, ensuring appropriate attributes like `loading="lazy"` (when images are below the fold) and explicit dimensions to prevent Cumulative Layout Shift (CLS).

## 1. Server-Side Rendering (SSR) and React Server Components (RSC)

By default, the App Router (v16.2) adopts Server Components first. Optimization through server-side rendering drastically reduces client load and the payload of downloaded bundles.

* **Data Fetching Colocation:** Always execute heavy business rules and API or database queries directly in Server Components (which operate under NodeJS/Edge) rather than on the client side (like `useEffect` + client fetch). This decreases client-server round trips and the size of delivered JavaScript.
* **Async APIs (Breaking Change):** In Next.js 16, `cookies()`, `headers()`, `params`, and `searchParams` are **fully asynchronous** — synchronous access has been removed. Always `await` these calls (e.g., `const cookieStore = await cookies()`). Failing to do so will throw a runtime error.
* **Opt-in Caching with `use cache`:** Next.js 16 defaults all dynamic code to execute at request time. Caching is now **explicit and opt-in** via the `"use cache"` directive. Mark Server Components or functions with `"use cache"` and control lifetime with `cacheLife()` and tags with `cacheTag()` to cache expensive computations. Use `updateTag()` inside Server Actions to immediately invalidate cached data.
* **Streaming and Partial Prerendering (PPR):** Partial Prerendering is now enabled via `cacheComponents: true` in `next.config` (replacing the former `experimental_ppr`). Wrap asynchronous data-dependent components in a `React.Suspense` Boundary (`<Suspense fallback={<Skeleton />}>`). This quickly sends the layout shell (static skeleton) to the client and gradually streams the dynamic part to immensely optimize LCP and TTFB.
* **Avoid Waterfalls:** When multiple server requests (Promises) are executed simultaneously in the same Server Component, ensure the use of `Promise.all` instead of declaring multiple sequential `await`s if one does not depend on the result of the other.
* **Granularity of Dynamism:** Functions like `cookies()`, `headers()`, and `searchParams` variables force the component into dynamic rendering. Try to group the use of dynamic functions at the lowest possible level contained within Suspenses and leverage `"use cache"` at higher levels to maximize static generation.
* **Server Components Rendering Performance (16.2):** Next.js 16.2 delivers a 25–60% reduction in Server Component HTML rendering time and up to 350% faster RSC payload deserialization on the client. No code changes are required — this is a runtime improvement. Update performance baselines taken on 16.1, as they are no longer representative.

## 2. `use client` Optimization (Client Components)

Client Components inject interactivity into the front-end but come with the imminent cost of increasing the JavaScript Main Thread weight, strongly impacting relative metrics (Input Delay, INP).

* **Leaves of the Tree:** Keep `use client` only at the terminal leaves of the UI interactivity tree (buttons, small forms, toggles). One of the worst practices in Next.js is declaring `'use client'` at the top level of the main page and accidentally transforming the entire subsequent component tree into client-rendering.
* **Server Components injected as Children:** A Client Component can indeed embrace Server Components, provided they are passed purely via `children` props in the composition. With this, child nodes do not magically become clients, preventing massive bundles.
* **RSC Payload Minimization (Optimized Props):** When passing information from a Server Component to a Client Component via Prop, never send unnecessarily fat nested objects (e.g., the complete record of a DB table). Extract only the truly essential variables (`Title`, `ID`, `Status`) on the client. Unprocessed payload leaks unnecessary serialization traffic.
* **Costly Interactions and Third-Party Imports:** Break free from ties, avoid loading heavy packages like `luxon`, `moment`, or huge utility libs exclusively on the client. Refactor these conversions and logs preferably to the Server.
* **React Compiler (Stable):** Next.js 16 ships with the stable React Compiler, which provides automatic memoization. Manual `useMemo`, `useCallback`, and `React.memo` are largely unnecessary — the compiler optimizes re-renders automatically. Remove manual memoization wrappers during refactoring to reduce code complexity without sacrificing performance.

## 3. Bundle, Code Splitting, and Static Resources

* **Turbopack (Default Bundler — Enhanced in 16.2):** Next.js 16 uses Turbopack as the default bundler for both `dev` and `build`, now delivering 400–900% faster compilation than webpack in 16.2 (200+ bug fixes since 16.1). New capabilities in 16.2: native **Subresource Integrity (SRI)** support (no external plugin needed), `postcss.config.ts` TypeScript support, improved tree shaking, and **Server Fast Refresh** (hot reloading of Server Components without full page reload — 67–100% faster server-side HMR). All improvements are active by default — no configuration changes needed.
* **Dynamic Imports (`next/dynamic`):** Mandatory module for huge UI elements that will **not** be immediately visible without user action (Complex Modals, Drawers, Heavy Data Visualization Charts). Use lazy load/dynamic imports aiming to postpone the First Load JS size.
* **Third-Party Scripts (`next/script`):** When importing trackers or Ad snippets, explicitly use the `<Script />` component. Leverage loading property strategies like `strategy="worker"` or `strategy="lazyOnload"` to avoid blocking the critical client parser.
* **Native Font Optimization:** Work with `next/font/google` or `next/font/local` during the inclusion of typographic fonts. Its engine pre-compiles the call and self-hosts preventing reflow and severe visual oscillation, eliminating FOUT/FOIT.
* **Intentional Caches with `use cache`:** Use the stable `"use cache"` directive combined with `cacheLife()` (to define TTL profiles) and `cacheTag()` (for targeted invalidation) to store expensive computations across multiple requests. Call `updateTag()` inside Server Actions for immediate cache invalidation. These replace the former `unstable_cache()` API.
* **Build Adapters (Now Stable):** The Build Adapters API graduated from alpha to stable in 16.2 — it allows platforms to customize the build output target beyond Vercel (Docker containers, custom Node servers, edge runtimes). If `next.config` references `experimental.buildAdapter`, remove the `experimental` wrapper. Relevant for all teams deploying to non-Vercel infrastructure.

## 4. Dev Server and Prefetch Performance (New in 16.2)

* **Dev Server Startup (87% faster):** The 16.2 dev server starts 87% faster than 16.1. Recalibrate DX metrics and CI scripts that measure startup time — no configuration needed.
* **`experimental.prefetchInlining`:** Bundles all route segment data (JS, RSC payload, CSS) into a single HTTP response at prefetch time, eliminating multiple parallel prefetch requests per link hover. Enable with `experimental: { prefetchInlining: true }` in `next.config`. **Trade-off:** the single bundled response is larger than any individual segment file — validate with Lighthouse or WebPageTest prefetch waterfall analysis before enabling in production.
* **View Transitions (`Link` `transitionTypes` prop):** The `<Link>` component now accepts a `transitionTypes` prop to hook into the browser View Transitions API for animated page navigation. Progressive enhancement — unsupported browsers fall back to instant navigation. No performance regression risk, but keep transition durations under 200ms to avoid INP impact.

## Quick Audit Cheat Sheet

1. Is there any import containing `"next/image"`? **[Remove immediately for a common `<img>` tag]**
2. Are there massive packages or very large `'use client'` declarations encompassing non-interactive root pages? **[Move to Leaves and isolate interactions]**
3. Is there a severely blocked screen load due to fetching the entire database JSON at once? **[Redesign employing `<Suspense>` and partial requests]**
4. Is the data sent from Server Components to Clients purified via a Data Transfer and devoid of huge superfluous data? **[Reduce the object exposed in Props]**
5. Are `cookies()`, `headers()`, `params`, or `searchParams` being accessed without `await`? **[Add `await` — synchronous access was removed in v16]**
6. Are there manual `useMemo`/`useCallback`/`React.memo` wrappers? **[Remove — React Compiler handles memoization automatically]**
7. Is caching still relying on `unstable_cache()` or implicit route caching? **[Migrate to `"use cache"` + `cacheLife()` + `cacheTag()`]**
8. Is `experimental.prefetchInlining` enabled? Has the prefetch payload size been measured (single bundled response vs. individual segment files) to confirm the trade-off is favorable for this application's link density? **[Validate with WebPageTest or Lighthouse network waterfall]**
9. Does `next.config` still reference `experimental.buildAdapter`? **[Build Adapters are now stable — remove the `experimental` wrapper if targeting non-Vercel infrastructure]**
