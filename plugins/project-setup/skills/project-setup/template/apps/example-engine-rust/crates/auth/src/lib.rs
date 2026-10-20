// auth: JWT validation with the shared JWT_SIGNING_KEY (api issues, engine validates), ACL checks, the axum extractor.
// identity.rs decides who a request acts as, including development sign-in under AUTH_ENABLED=FALSE. The extractor
// gathers the peer, the headers and the JWT check, calls identity::authenticate, and answers Refused with 401.

pub mod identity;
