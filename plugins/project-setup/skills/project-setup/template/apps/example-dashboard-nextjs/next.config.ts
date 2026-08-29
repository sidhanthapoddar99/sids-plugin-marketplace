// Next.js server. basePath comes from .env.proxy, read directly, no fallback:
//   const basePath = process.env.DASHBOARD_PREFIX; if (!basePath) throw new Error("DASHBOARD_PREFIX is not set — run ctl dev dashboard");
//   output: "standalone", basePath,
//   rewrites: dev only — `${process.env.API_PREFIX}/:path*` → `http://127.0.0.1:${process.env.API_PORT}${process.env.API_PREFIX}/:path*`
// Under docker, compose passes DASHBOARD_PREFIX as a build arg and API_HOST / API_PORT at runtime.
