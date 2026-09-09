// The one server boundary for the browser side: nothing outside lib/api calls fetch(). Same rules as the Vite shape.
// Server components fetch by service name (API_HOST) in the page; the browser calls `/api` on its own origin through here.
