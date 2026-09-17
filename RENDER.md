# OmniRoute on Render

This repository includes a Render Blueprint in `render.yaml` for a persistent Docker deployment.

## Deployment

1. In Render, choose **New → Blueprint**.
2. Connect `iamakhilan/OmniRoute`.
3. Select the `release/v3.8.51` branch.
4. Review the generated environment variables and create the service.
5. The service listens on Render's public HTTPS endpoint and exposes the OpenAI-compatible API under `/v1`.

## Persistent data

OmniRoute stores its application database and runtime state in `/app/data`. The Blueprint mounts a Render persistent disk at that path.

A persistent disk requires a Render paid service plan. If you do not need persistence for a temporary test, remove the `disk` section and use a non-persistent deployment.

## Codex / WebSocket

The Blueprint generates `OMNIROUTE_WS_BRIDGE_SECRET`. Render terminates TLS at the edge, so clients connect to the public service using `wss://` when a WebSocket connection is required.

## API clients

Use the Render service URL as the OpenAI-compatible base URL, for example:

`https://YOUR-SERVICE.onrender.com/v1`

Keep `REQUIRE_API_KEY=true` enabled for a public deployment and use an OmniRoute API key from the dashboard.

## Notes

The Dockerfile already binds the runtime to `0.0.0.0:20128`, uses a non-root runtime user, and stores persistent state under `/app/data`. The Render configuration therefore avoids modifying the application runtime just to satisfy Render's container requirements.
