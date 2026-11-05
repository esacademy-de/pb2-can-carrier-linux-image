# Extra packages for the apt repository

Put small packages here and push; the `publish-apt` workflow adds them to the
signed repository (https://esacademy-de.github.io/pb2-can-carrier-linux-image/):

* binary packages: `*.deb` (arm64 or all)
* source packages: the `*.dsc` plus the files it lists (`*.orig.tar.*`,
  `*.debian.tar.*` or `*.diff.gz`)

Large files (kernel packages, big applications) do not belong in git: attach
them to the GitHub release tagged `apt-pool` instead; the workflow picks up all
of its assets. A package must have a higher version than the one it replaces.
Only the newest 3 versions of each package are kept online.
