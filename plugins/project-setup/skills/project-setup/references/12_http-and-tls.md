# HTTP and TLS deployment options

TLS is deployment configuration, separate from application code. Keep the existing Nginx edge and its frontend/API routing; choose where HTTPS terminates.

| Option | Traffic flow | Certificate management |
|---|---|---|
| Central Traefik | Browser HTTPS → Traefik → Nginx HTTP service | Configure a Traefik ACME resolver and attach it to the app's TLS router; Traefik then obtains and renews certificates. |
| Cloudflare Tunnel | Browser HTTPS → Cloudflare → tunnel → Nginx HTTP service | Cloudflare manages the edge certificate. Configure the tunnel's service URL to reach Nginx. |
| ngrok | Browser HTTPS → ngrok → tunnel → local Nginx HTTP port | ngrok manages the public HTTPS endpoint's certificates. Point the tunnel at the app's published frontend port. |
| Direct Nginx HTTP | Browser HTTP → published HTTP port → Nginx; optionally configure HTTPS directly on Nginx | HTTP needs no certificate. For HTTPS, add a TLS listener, a certificate and private key, and an ACME client for issuance and renewal. |

For the first three options, the application can continue serving HTTP behind the TLS endpoint. Keep that connection on the local tunnel or a trusted private network; use HTTPS upstream when the connection crosses an untrusted network. Cloudflare's ordinary DNS proxy is different from Tunnel: use Full (strict) with a valid origin certificate for an HTTPS origin.

## Ports and optional public settings

Local Docker uses the frontend owner's port through `+expose_web`. Keep `PUBLIC_URL`, `HTTP_PORT`, and `HTTPS_PORT` commented out until the chosen deployment needs them. `PUBLIC_URL` is useful when an app must generate absolute links or callbacks; it does not configure DNS or certificates.

The `+public` modifier provides alternative port mappings and public-URL injection. Port numbers are configurable: mapping `443:8443` only forwards traffic; it does not enable TLS. The shipped Nginx templates listen on HTTP port 8080. A mapping to 8443 requires a separately configured TLS listener.

When using a central proxy, route it to Nginx on the shared Docker network, or to the app's published HTTP port when the proxy runs on the host. Only the proxy needs to expose public HTTPS. Select the exposure modifier appropriate to that topology.

## Direct HTTPS without public HTTP

Configure an Nginx TLS listener on 8443, mount the certificate and key read-only, and publish only the chosen HTTPS port. Use a separate HTTPS-only modifier: the current `+public` requires both port variables and publishes both ports. Do not combine it with another exposure modifier expecting ports to be removed; Compose port lists merge.

Use an ACME client such as Certbot with DNS-01 validation when public port 80 must remain closed. HTTP-01 requires public port 80. Arrange automatic renewal and an Nginx reload after renewal. With no HTTP listener, plain `http://` requests will not redirect to HTTPS.

## Provider setup references

- [Traefik ACME certificate resolvers](https://doc.traefik.io/traefik/master/https/acme/)
- [Cloudflare Tunnel setup](https://developers.cloudflare.com/tunnel/setup/) and [origin TLS](https://developers.cloudflare.com/ssl/get-started/)
- [ngrok HTTPS endpoints](https://ngrok.com/docs/http)
- [Let's Encrypt challenge types](https://letsencrypt.org/docs/challenge-types/) and [Nginx HTTPS configuration](https://nginx.org/en/docs/http/configuring_https_servers.html)
