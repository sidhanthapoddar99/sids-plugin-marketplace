// output: "export" — pure static HTML in out/, served by the web nginx image at /. No Node at runtime.
// basePath: "" (it is the root). trailingSlash: true so nginx maps /about/ → /about/index.html.
// images: { unoptimized: true } (no image server in a static export).
// No rewrites: a static export cannot proxy. In dev the browser reaches /api through `ctl dev --proxy`.
