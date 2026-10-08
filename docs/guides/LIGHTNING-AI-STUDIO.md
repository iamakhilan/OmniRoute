# OmniRoute on Lightning AI Studio

This setup is designed for a long-lived OmniRoute Studio.

## Persistence

Lightning AI Studios persist the Studio home directory across stop/restart. Lightning documents `/teamspace/studios/this_studio` as part of that persistent Studio home. OmniRoute is explicitly configured by the Lightning launcher to use:

`/teamspace/studios/this_studio/.omniroute`

That directory contains the SQLite database, backups, logs, and provider configuration. Provider API keys created in the OmniRoute dashboard therefore remain after a Studio restart.

## Secrets

Do **not** commit API keys or encryption keys to this repository.

Create these as Lightning AI **User Secrets** or **Teamspace Secrets**:

- `JWT_SECRET`
- `API_KEY_SECRET`
- `STORAGE_ENCRYPTION_KEY`
- `OMNIROUTE_API_KEY`

These must remain unchanged for the lifetime of the Studio/database. In particular, changing `STORAGE_ENCRYPTION_KEY` makes previously encrypted provider credentials undecryptable.

Lightning Secrets are encrypted by Lightning AI and injected as environment variables when the Studio runs.

## Public URL

Run OmniRoute on the fixed port `20128` and expose that port with Lightning's Ports plugin.

If you have a fixed public URL, set:

```
NEXT_PUBLIC_BASE_URL=https://your-fixed-public-url
```

as a persistent Studio environment variable. The launcher does not generate or rotate a public URL; keep the same Lightning-exposed port/public URL and store it in `NEXT_PUBLIC_BASE_URL` if you want OmniRoute to display it consistently. The Lightning Studio/port exposure is responsible for the external URL.

The same Studio and exposed port should be reused after restart; restarting the Studio does not recreate its persistent filesystem.

## Start

From the repository root:

```
npm run lightning:start
```

The launcher refuses to start if the four required persistent secrets are missing. This prevents the common failure where a restarted Studio creates a new encryption/JWT identity and existing credentials stop working.

## Important

If you delete the Studio itself rather than stopping/restarting it, do not assume its local filesystem is retained. For production use, Lightning's persistent Drive or a Lightning Deployment can be used for stronger lifecycle guarantees.
