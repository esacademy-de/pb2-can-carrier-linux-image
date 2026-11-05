# PB2 CAN Carrier package repository

A signed apt repository, served as a static website (GitHub Pages) from this
repository's `publish-apt` workflow:

    https://esacademy-de.github.io/pb2-can-carrier-linux-image/

It delivers `pb2-can-carrier-support` (carrier overlay, SD-card configuration,
power-off handling, the apt pin that keeps the carrier kernel), the carrier
kernel, and further applications and source packages.

## One-time setup (repository owner)

1. Repository **Settings → Pages → Build and deployment → Source: GitHub Actions**
   (the repository's own settings, not the organization's).
2. Repository **Settings → Secrets and variables → Actions → New repository
   secret**: name `APT_SIGNING_KEY`, value = the complete contents of the
   ASCII-armored private key (`-----BEGIN PGP PRIVATE KEY BLOCK-----` ...). The
   matching public key is `apt/pb2-can-carrier-archive-key.asc`. Keep a
   backup of the private key somewhere safe; it never goes into this repository.
3. Run the workflow once (Actions → publish-apt → Run workflow).

## On a board

Images built from this repository already have the repository configured, so
this is all it takes to get updates:

    sudo apt update && sudo apt upgrade

A board with an older image gets the repository once, by hand:

    sudo curl -fsSLo /usr/share/keyrings/pb2-can-carrier-archive-keyring.gpg \
        https://esacademy-de.github.io/pb2-can-carrier-linux-image/pb2-can-carrier-archive-keyring.gpg
    printf 'Types: deb\nURIs: https://esacademy-de.github.io/pb2-can-carrier-linux-image/\nSuites: ./\nSigned-By: /usr/share/keyrings/pb2-can-carrier-archive-keyring.gpg\n' \
        | sudo tee /etc/apt/sources.list.d/pb2-can-carrier.sources
    sudo apt update && sudo apt install pb2-can-carrier-support

(Check the key against the fingerprint in `apt/pb2-can-carrier-archive-key.asc`:
`37874330451F08C42026287FFB5DDB0E44975DDF`.)

## How packages get in

The `publish-apt` workflow (`.github/workflows/publish-apt.yml`) builds
`pb2-can-carrier-support` from `image/`, `dts/` and `apt/support/`, adds
everything it finds in

* `packages/` in this repository (small packages: `*.deb`, or source packages
  as `*.dsc` + the files it lists), and
* the assets of the GitHub release tagged `apt-pool` (large files such as
  kernel packages),

indexes them (`Packages`, `Sources`), signs `Release` with the key held in the
repository secret `APT_SIGNING_KEY` and publishes the result. Only the newest 3
versions of each package are kept (a GitHub Pages site is limited to about 1 GB).
Packages must have a higher version than the one they replace.

The workflow runs on pushes to `master` that touch these inputs, and by hand
(Actions tab → publish-apt → Run workflow).

## Source packages

Add `Types: deb deb-src` to `/etc/apt/sources.list.d/pb2-can-carrier.sources`,
then `apt source <package>` fetches the source.

## Key rotation

The public key lives in `apt/` and ships in `pb2-can-carrier-support`. To
rotate: create a new key, publish a support package version that contains
both keyrings, wait until boards have updated, then switch the secret to the
new key.
