// The outermost shell, rendered around every route: providers (QueryClient, theme), the error boundary, <Outlet/>.
// It picks no layout; layouts are chosen by the pathless layout routes below (_app.tsx) or per route.
// A route file is thin: it picks a layout and mounts one module. It never imports lib/api or calls fetch().
