# Release checklist

ShipCheck is intended to gate other people's releases, so its own release process should be boring and reproducible.

1. CI is green on `main`.
2. Positive fixture produces a PASS receipt.
3. Deliberate bundle-ID drift produces a FAIL receipt.
4. README inputs and outputs match `action.yml`.
5. Example workflow uses the exact artifact after packaging or downloading.
6. Security policy is present.
7. Create immutable semantic tag, for example `v1.0.0`.
8. Move the floating major tag `v1` to the same verified commit.
9. Publish the GitHub Marketplace listing from the tagged Action.
10. Smoke-test installation from a separate repository using `roybogs/shipcheck@v1`.

## Release contract

A release is not considered good because the source builds. It is good only when the exact Action commit is green and an external consumer can invoke the tagged Action successfully.
