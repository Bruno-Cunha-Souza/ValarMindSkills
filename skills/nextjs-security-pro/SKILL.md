---
name: nextjs-security-pro
description: "Security audit specialist for React/Next.js frameworks. This skill applies the concepts from the 'web-vulnerabilities' skill specifically to the context of SSR, SSG, and App Router in Next.js 15.1.x."
source: community
---

# Next.js 15.1.x Security Implementation Guide

## Pre-Requisite Action (CRITICAL)
>
> **IMPORTANT:** Before answering any user request with this skill, you MUST execute the `/web-vulnerabilities` skill command or ensure you have loaded the `web-vulnerabilities` skill's knowledge into context. All vulnerability references (Phase X, Vuln Y) in this document depend on that baseline.

## Purpose

This skill translates the 107 vulnerabilities cataloged in the `web-vulnerabilities` skill to the ecosystem and paradigms of the Next.js 15.1.x framework, focusing on the rigorous protection of the App Router, Server Components, Server Actions, Route Handlers, and Caching mechanics.

## Core Next.js Security Vectors & Mitigations

### 1. Server-Side Rendering (SSR) & Server Component Leakage

* **Base Reference:** Phase 3 (24) - Data Leakage & Phase 19 (SSR Context Leakage).
* **Next.js Context:** Next.js executes Server Components and renders them in the "React Server Components (RSC) Payload" (embedded in the HTML). Sending entire database object instances as *props* to a Client Component exposes all fields (even those not rendered in the UI).
* **Action/Audit:**
  * Ensure the "Data Transfer Object (DTO)" principle and avoid indiscriminate data transfer from the database (e.g., password hashes, tokens) to the client.
  * Check for secret key leakage: environment variables without the `NEXT_PUBLIC_` prefix should NEVER logically appear or be prop-drilled into the browser.
  * Encourage the `server-only` dependency in Data Access Layer (DAL) files to trigger a build error if they are mistakenly imported into the front-end.

### 2. Insecure Server Actions

* **Base Reference:** Phase 6 (40) - Inadequate Authorization & Phase 8 - API Security.
* **Next.js Context:** Server Actions (`"use server"`) are implicit RPC (Remote Procedure Call) endpoints exposed to the web. Without manual protections within the Action's code, the middleware or layout above do not provide complete security.
* **Action/Audit:**
  * Validate that **EVERY SINGLE** *Server Action* checks for authentication and authorization (e.g., `await auth()` from NextAuth) BEFORE executing sensitive code (database mutations).
  * Inputs in Actions must be sanitized and strictly validated with `Zod` or similar parsers providing full Type-Safety guarantees.
  * Implement aggressive *Rate Limiting* by UserID or IP. The Next.js framework will not do this natively.

### 3. Dangerous Patterns in JSX

* **Base Reference:** Phase 1 (2) - XSS & Phase 10 (56) - DOM-based XSS.
* **Next.js Context:** React automatically escapes strings injected into JSX. The danger arises from the explicit use of `dangerouslySetInnerHTML` or links of type `javascript:`.
* **Action/Audit:**
  * Audit `dangerouslySetInnerHTML`. If it is mandatory, validate whether the HTML string was processed by a robust sanitizer, such as `DOMPurify` or `sanitize-html`.
  * Audit hyperlinks of type `<a href={userInput}>`, warning against restricted schemes like `javascript:` and `data:`.

### 4. Cache Poisoning and Static Data Leakage

* **Base Reference:** Phase 10 (58) - Browser Cache Poisoning / Phase 3 Sensitive Data.
* **Next.js Context:** Next.js aggressively builds and caches responses in the Next.js Cache (Data Cache and Full Route Cache). If a route uses private request data without signaling the router, confidential user content may leak to others via cache hits.
* **Action/Audit:**
  * Identify pages or Route Handlers that return sensitive or user-specific data, ensuring the use of strict explicit dynamic functions: `cookies()`, `headers()`, or the explicit constructor `export const dynamic = "force-dynamic"`.
  * Evaluate strict headers such as `Cache-Control`.

### 5. Middleware Auth Bypass

* **Base Reference:** Phase 6 (40, 43) - Forceful Browsing, Inadequate Authorization.
* **Next.js Context:** Centralized checking in `middleware.ts` at the *Edge* resolves quick validations (visual route guards), but it is vulnerable if the `matcher` Regex has holes for subroutes (e.g., `/admin/.` or files).
* **Action/Audit:**
  * Enforce that protections do not exist solely in the Middleware (Defense in Depth). APIs and Actions must also re-perform critical authentication/permission checks.
  * Be careful when using custom headers injected by the middleware, such as `x-forwarded-for` on the request object for IP validations (they can be subject to IP Spoofing).

### 6. SSRF (Server-Side Request Forgery) in Image Optimization

* **Base Reference:** Phase 12 (66) - SSRF.
* **Next.js Context:** The Next.js Server acts as an Optimizing Proxy for external `<Image />` components.
* **Action/Audit:**
  * Audit the `next.config.mjs` config file, ensuring there are no overly permissive wildcards in `images.remotePatterns` (e.g., `hostname: '*'`). An open wildcard exposes the Vercel/Next.js infrastructure to Server-Side abuse (SSRF) accessing closed ports and financial exhaustion via Optimization limit DoS.

### 7. CSRF in Server Actions Integration

* **Base Reference:** Phase 10 - Insecure Cross-Origin Communication.
* **Next.js Context:** The App Router blocks CSRF attacks for functions generated as *Server Actions* (Post Actions) by natively checking the Header/`Origin` directive via the framework.
* **Action/Audit:**
  * Alert for GET Route Handlers or URL Params-based state manipulations that cause server-side mutating side-effects. GETs must never cause data mutation. POST Route Handlers in `app/api/...` require strict checks or auxiliary anti-CSRF frameworks when not using Next.js protections.

## Quick Audit Cheat Sheet Next.js 15

During a PR Review on projects with Next.js v15.1.x, execute the essential Check-list validations:

1. `server-only`: Does the `import "server-only"` module exist in Database logic or private Helpers? [Ref: Web Vuln ID 24]
2. `use server`: Do *Server Actions* functions perform an authentic control check before querying (e.g., `await auth()`)? Do they use `z.object().parse` against payloads injected into the RPC input? [Ref: Web Vuln ID 40, 48]
3. RSC Leakage: Do Server Components pass the entire instance of the Object Model as a *Prop* to the UI element? (e.g., `<table clientComponent={fullDBResult} />`) [Ref: Web Vuln ID 24, 33]
4. Custom Regex Router: Is there an inconsistency in the `matcher` inside the `middleware.ts` file leaving API paths exposed? [Ref: Web Vuln ID 43]
5. Remote Patterns: Is the configuration of remote hostnames in the `next.config` file limited to exact origins in the image optimizer's object literal? [Ref: Web Vuln ID 66]
6. XSS / JSX Bypass: Does the page have strings rendered in `dangerouslySetInnerHTML`? Were they sanitized with `DOMPurify.sanitize(input)` beforehand? [Ref: Web Vuln ID 2, 56]

---

## When to Use

This skill should be applied whenever there is a request to analyze, review, write, or refactor modern Next.js 15.1.x React applications (App Router) in the context of identifying framework-specific security pitfalls, vulnerability mitigation, and architectural best practices.
