# Vendored test frameworks

These directories are **vendored copies** (not git submodules) of the bats test
framework and its helper libraries. Vendoring — rather than submoduling — is the
locked decision (AR `analyzing-0.md#q1-bats`, AD-1): AC-1 requires an **offline
clean-clone bootstrap**, and a submodule would require `git clone
--recurse-submodules` *with network* to populate. Vendored copies are present on
any plain `git clone`, giving zero-network determinism.

## Provenance (pinned)

| Library        | Upstream                                          | Pinned tag | Pinned SHA                                 |
|----------------|---------------------------------------------------|------------|--------------------------------------------|
| `bats-core`    | https://github.com/bats-core/bats-core.git        | v1.11.0    | `5da66876b8b619235aee1eb3e54954eaca88059b` |
| `bats-support` | https://github.com/bats-core/bats-support.git     | v0.3.0     | `24a72e14349690bcbf7c151b9d2d1cdd32d36eb1` |
| `bats-assert`  | https://github.com/bats-core/bats-assert.git      | v2.1.0     | `78fa631d1370562d2cd4a1390989e706158e7bf0` |

Licenses: bats-core — MIT; bats-support / bats-assert — Creative Commons CC0 1.0
(public domain). Each library's `LICENSE` file is retained in its directory.

Excluded from the vendored copy to keep the repo lean: `.git/`, `.github/`,
`docs/`, `man/`, CI config (`.travis.yml`, `.appveyor.yml`). The runtime surface
(`bin/`, `libexec/`, `lib/`, `load.bash`, `src/`) is kept intact.

## Refresh recipe (reversibility path — AD-1)

To update a vendored library to a new pinned release:

```bash
TAG=v1.12.0                      # the new release to pin
LIB=bats-core                    # one of: bats-core, bats-support, bats-assert
URL=https://github.com/bats-core/$LIB.git

tmp=$(mktemp -d)
git clone --quiet --depth 1 "$URL" "$tmp"
git -C "$tmp" fetch --quiet --depth 1 origin tag "$TAG"
git -C "$tmp" checkout --quiet "refs/tags/$TAG"
SHA=$(git -C "$tmp" rev-parse HEAD)

rm -rf "tests/vendor/$LIB"
mkdir -p "tests/vendor/$LIB"
( cd "$tmp" && tar --exclude='.git' --exclude='.github' --exclude='docs' \
      --exclude='man' --exclude='.gitignore' --exclude='.travis.yml' \
      --exclude='.appveyor.yml' -cf - . ) | ( cd "tests/vendor/$LIB" && tar -xf - )

# Then update the table above with $TAG and $SHA, and commit.
rm -rf "$tmp"
```

After refreshing, run `./run-tests.sh` to confirm the new copy bootstraps and the
suite stays green.
