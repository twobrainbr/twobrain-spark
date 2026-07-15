# NERK commerce integration

The NERK integration is disabled by default and is configured centrally. It is
not exposed as a self-service integration to regular account administrators.

## Activation

1. In NERK Admin, create a read-only API token using the `Chatwoot` preset.
2. In Spark Super Admin, open installation settings and configure the NERK API
   base URL and token.
3. In Spark Super Admin, open the target account and enable the
   `nerk_integration` account feature.
4. For the NERK Website inbox, enable identity validation and configure the
   same HMAC secret in the NERK storefront.

Both conditions are required: a valid installation-level configuration and the
account feature. This keeps NERK hidden from other companies in the 2Brain
group while allowing the same integration architecture to be enabled for a
specific account.

## Data access

The conversation sidebar resolves the contact by email or phone and shows the
customer summary, all orders, totals, payment state, refunds, returns and
shipments. API credentials remain on the Spark server and are never sent to the
agent browser.

Captain can answer generic product and public-promotion questions without a
customer identity. Personal tools for orders, tracking and NERK Club require a
Website inbox contact whose HMAC identity was verified. When verification is
missing, the assistant must ask the customer to sign in to NERK and reopen the
chat instead of returning personal information.

The NERK token should contain only these read scopes:

- `catalog:read`
- `promotions:read`
- `customers:read`
- `orders:core:read`
- `payments:read`
- `logistics:read`
- `returns:read`
- `loyalty:read`
- `commerce_context:read`
