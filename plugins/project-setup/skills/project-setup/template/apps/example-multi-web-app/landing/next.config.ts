// output: "export" — pure static HTML in out/, served by the web nginx image at /. No Node at runtime.
// basePath: process.env.NEXT_PUBLIC_BASE_PATH === "/" ? "" : (process.env.NEXT_PUBLIC_BASE_PATH ?? "")
//   — WEB_LANDING_PREFIX from .env.proxy, a build arg under `ctl build`; Next wants "" for the root.
// trailingSlash: true so nginx maps /about/ → /about/index.html. images: { unoptimized: true }.
// A site name is a literal in the layout, never an env value.
// No rewrites: a static export cannot proxy. In dev the browser reaches /api through `ctl dev --proxy`.
