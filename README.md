# VeraId Authority

VeraId Certificate Authority (CA) server.

## Environment variables

- `AUTHORITY_VERSION` (required). The version of this server.
- `MONGODB_URI` (required).
- OAuth2 authentication:
  - `OAUTH2_JWKS_URL` (required). The URL to the JWKS endpoint of the authorisation server.
  - Either `OAUTH2_TOKEN_ISSUER` or `OAUTH2_TOKEN_ISSUER_REGEX` (required). The (URL of the) authorisation server.
  - `OAUTH2_TOKEN_AUDIENCE` (required). The identifier of the current instance of this server (typically its public URL).

## Development

This app requires the following system dependencies:

- Node.js 18.
- Kubernetes 1.22+ (we recommend [Minikube](https://minikube.sigs.k8s.io/docs/start/) with Docker).
- [Knative](https://knative.dev/docs/install/quickstart-install/#install-the-knative-cli) v1.9+.
- [Skaffold](https://skaffold.dev/docs/install/) v2.1+.

To start the app, simply run:

```
skaffold dev
```

You can find the URL to the HTTP server by running:

```
kn service describe veraid-authority -o url
```

## Architecture

This multi-tenant server will allow one or more organisations to manage their VeraId setup, and it'll also allow organisation members to claim and renew their VeraId Ids.

## API

### Authentication and authorisation

We use OAuth2 with JWKS to delegate authentication to an external identity provider.

The API employs the following roles:

- Admin. They can do absolutely anything on any organisation.
- Org admin. They can do anything within their own organisation.
- Org member. They can manage much of their own membership in their respective organisation.

### HTTP Endpoints

It will support the following API endpoints, which are to be consumed by the VeraId CA Console (a CLI used by organisation admins) and VeraId signature producers (used by organisation members):

Unless otherwise specified, all inputs and outputs will be JSON serialised.

- `POST /orgs`: Create org.
  - Auth: Admin.
  - Input:
    - Name (e.g., `acme.com`).
    - Member access type (`invite-only` or `open`).
    - [Awala endpoint middleware](https://github.com/relaycorp/relayverse/issues/28) URL (optional).
  - Output:
    - VeraId TXT record.
- `GET /orgs/{orgName}`: Get org.
  - Auth: Org admin.
  - Output: Same as input to `POST /orgs`.
- `PATCH /orgs/{orgName}`: Modify org.
  - Auth: Org admin.
  - Input: Same as `POST /orgs`, but org name can't be changed.
- `DELETE /orgs/{orgName}`: Delete org.
  - Auth: Org admin.
- `POST /orgs/{orgName}/members`: Create member.
  - Auth: Org admin.
  - Input:
    - Name (used in VeraId member certificates; `null` if member is a bot).
    - Email (optional; needed if they'll access this API, not needed if they'll use Awala).
    - Role: `org_admin` or `regular`.
  - Output:
    - URL to the new member on this API.
- `GET /orgs/{orgName}/members/{memberId}`: Get member.
  - Auth: Org admin.
- `PATCH /orgs/{orgName}/members/{memberId}`: Modify member.
  - Auth: Org admin.
  - Input: Same as in `POST /orgs/{orgName}/members`.
- `DELETE /orgs/{orgName}/members/{memberId}`: Delete member.
  - Auth: Org admin.
- `POST /orgs/{orgName}/members/{memberId}/public-keys`: Register public key for member.
  - Auth: Org member.
  - Input:
    - The DER-encoded public key.
    - The OID for the service where the respective bundles will be valid (e.g., `1.2.3.4.5`).
  - Output: The URL for the new key.
- `DELETE /orgs/{orgName}/members/{memberId}/public-keys/{keyId}`: Unregister public key for member.
  - Auth: Org member.
  - Input: None.
  - Output: Nothing.
- `GET /orgs/{orgName}/members/{memberId}/public-keys/{keyId}/bundle`*: Get VeraId Member Bundle for a given public key.
  - Auth: Org member.
  - Output: VeraId Member Bundle.
- `POST /orgs/{orgName}/members/{memberId}/public-key-import-tokens`: Generate single-use token to import a member public key.
  - Auth: Org member.
  - Input:
    - The OID for the service where the respective bundles will be valid (e.g., `1.2.3.4.5`).
  - Output: A single-use UUID4.
- `POST /awala`: [Awala endpoint middleware](https://github.com/relaycorp/relayverse/issues/28) backend.
  - Auth: Awala Endpoint Middleware.
  - Incoming service messages:
    - `MemberIdRequest`. Payload (`application/json`):
      - The id for the respective member public key.
      - The current timestamp.
      - Digital signature for the parameters above, produced with the private key associated with the public key.
    - `MemberPublicKeyImport`. Payload (`application/json`):
      - The single-use import token.
      - The DER-encoded public key.
  - Outgoing service messages:
    - `MemberIdBundle`.
      - Trigger: Successful `MemberIdRequest`.
      - Payload (`application/vnd.veraid.member-bundle`): VeraId Member Bundle.
    - `MemberPublicKeyImportAck`.
      - Trigger: Successful `MemberPublicKeyImport`.
      - Payload (`application/json`):
        - The id for the member public key. This is to be passed in subsequent `MemberIdRequest` messages.
        - VeraId Member Bundle.

\* We may skip this endpoint in v1 because the endpoint `POST /awala/` already supports this functionality.

This server will have the following background processes:

- [Awala endpoint middleware](https://github.com/relaycorp/relayverse/issues/28) backend. Used to respond to the requests made to `POST /orgs/{orgName}/awala/`.
