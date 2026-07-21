# MediaRemote Adapter

Chimlo bundles the `MediaRemoteAdapter.framework` helper and its Perl launcher
to read system Now Playing metadata, including cover artwork, on macOS 15.4 and
later. The lightweight `MRNowPlayingRequest` API does not expose artwork there.

- Upstream: https://github.com/ungive/mediaremote-adapter
- Bundled implementation: the adapter shipped by Atoll at commit
  `c28eb8226ffba4db8d37ae91a34902226753d7cb`
- License: BSD 3-Clause, reproduced in `LICENSE`
