// The one server boundary. Nothing outside api/ calls fetch().
// Owns: the endpoint paths (the only place a URL string exists), zod at the response edge
// (types inferred with z.infer), one app-wide error shape, and the query keys beside the
// functions they cache. Base paths from the prefixes: `/api`, `/engine`. Attaches the JWT.
// Files group by the backend's domain vocabulary: api/users.ts, api/orders.ts — never by screen.
