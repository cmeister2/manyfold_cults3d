# Cults3D for Manyfold

List your purchased and downloaded free Cults3D models in Manyfold, link existing models, and sync metadata and images.

## Install

Requires Manyfold 0.146.0 or newer. Importing and linking require administrator access.

1. Download `manyfold_cults3d.zip` from the [latest release](https://github.com/cmeister2/manyfold_cults3d/releases/latest).
2. Upload it under **Settings > Plugins**, then restart Manyfold. Keep the ZIP filename unchanged when installing updates.
3. Set your **Cults3D username** and **API key** under **Settings > Integrations**. Generate a key on [Cults3D](https://cults3d.com/en/api/keys).

See Manyfold's [plugin installation guide](https://manyfold.app/sysadmin/plugins) for plugin directory setup.

## Use

Open **Providers > Cults3D > Import** and select **Refresh library** to load your purchased and previously downloaded free models. Refreshes update saved entries and remove ones no longer in your Cults3D library. Manyfold models and files are always kept. Failed refreshes leave the saved list unchanged.

**Status** shows your saved library and its links to Manyfold models. Choose **Create Model** on an unlinked entry to create a model and queue metadata and image sync. This requires a default Manyfold library.

To link an existing Manyfold model, choose **Link to Cults3D** from its menu. Select a suggested library match with **Use this model**, or enter a Cults3D model URL, slug, or ID, then select **Link and sync**.

Sync imports the name, description, printing details, tags, license, creator, and images. Download 3D files from Cults3D and import them into Manyfold separately; the plugin cannot download them through the API.

## Development

Copy `.env.example` to `.env` and set `CULTS3D_USERNAME` and `CULTS3D_API_KEY`. These environment variables override Manyfold's integration settings.

Start the development instance with Docker Compose:

```sh
docker compose up --build -d
```

Open <http://localhost:3215>. An administrator and default library are created automatically. Data persists in the Compose volume. After code changes, run `docker compose restart manyfold`.

Run plugin and package tests with Python 3 and Docker:

```sh
bin/test
```

Tests use disposable containers and mocked API responses. Release tooling tests require Node 24.15 or newer:

```sh
npm ci --ignore-scripts
npm run test:release
```

Build a plugin ZIP with an explicit version:

```sh
python3 bin/package 1.0.0
```

The archive is written to `dist/manyfold_cults3d.zip`. Releases publish automatically from `main` using Conventional Commits; `npm run release:dry-run` previews the next release.
