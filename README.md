<div align="center">

<a href="https://github.com/cashstratum/cashstratum"><img src="https://raw.githubusercontent.com/cashstratum/cashstratum/main/.github/assets/cashstratum-bch-transparent-v2.png" alt="CashStratum — Bitcoin Cash (BCH) Stratum server and solo mining pool software" width="560"></a>

# ➡️ This project now lives at [cashstratum/cashstratum](https://github.com/cashstratum/cashstratum)

### This BCH CKPool fork became **CashStratum**, and that is where it is actively maintained.

[![Go to CashStratum](https://img.shields.io/badge/GO%20TO-cashstratum%2Fcashstratum-009E61?style=for-the-badge&logo=github&logoColor=white&labelColor=030711)](https://github.com/cashstratum/cashstratum)
[![Latest release](https://img.shields.io/github/v/release/cashstratum/cashstratum?style=for-the-badge&label=LATEST%20RELEASE&color=0AC18E&labelColor=030711)](https://github.com/cashstratum/cashstratum/releases/latest)
[![Status](https://img.shields.io/badge/THIS%20REPO-NOT%20MAINTAINED-9E9E9E?style=for-the-badge&labelColor=030711)](#-what-this-means-for-this-repository)

**[Repository](https://github.com/cashstratum/cashstratum)** ·
**[Releases](https://github.com/cashstratum/cashstratum/releases)** ·
**[Install guide](https://github.com/cashstratum/cashstratum/blob/main/docs/installation.md)** ·
**[Block proofs](https://github.com/cashstratum/cashstratum/tree/main/docs/proofs)** ·
**[cashstratum.com](https://cashstratum.com)**

</div>

---

> [!IMPORTANT]
> **`skaisser/ckpool` is no longer actively maintained.** It receives no new features, fixes or
> security updates. All development, releases, issues and pull requests have moved to
> **[cashstratum/cashstratum](https://github.com/cashstratum/cashstratum)**.

## 🚚 Why it moved

This repository started as a production CKPool fork for Bitcoin Cash, released as *EloPool* and
later *BlockSniper.ai*. It has grown into **CashStratum**, an open-source BCH Stratum server and
solo mining pool engine with its own home, release process and community:

- **Same lineage, actively developed.** CashStratum continues this fork's code: native CashAddr,
  direct per-address on-chain solo payouts, a configurable operator fee and multi-node failover,
  rebased onto upstream CKPool 1.2.0.
- **Security hardening that never reached this repository.** CashStratum 1.2.1 adds stricter
  difficulty bounds and share accounting, append-only share logs, strict client framing, and full
  support for block templates above 65,535 transactions.
- **Verifiable track record.** **69 BCH mainnet blocks** from this lineage, each checked against
  public chain data, with the evidence published in
  [`docs/proofs/`](https://github.com/cashstratum/cashstratum/tree/main/docs/proofs).
- **Tagged, reproducible releases.** You can build exactly what the reference deployment runs.
  The Go operator API and block notifier, installers, unit tests and a regtest gate all ship
  together.
- **Vendor-neutral.** CashStratum is the software. [blocksniper.ai](https://blocksniper.ai) is one
  production pool running it, and any operator can run their own.

## 🧭 What this means for this repository

| If you… | Do this |
|---|---|
| Want to run a BCH pool or solo-mine BCH | Use **[cashstratum/cashstratum](https://github.com/cashstratum/cashstratum)** and its [latest release](https://github.com/cashstratum/cashstratum/releases/latest) |
| Run a pool built from this repository | Plan your upgrade with the [CashStratum install guide](https://github.com/cashstratum/cashstratum/blob/main/docs/installation.md) |
| Found a bug or have a feature request | Open it at [cashstratum/cashstratum/issues](https://github.com/cashstratum/cashstratum/issues) |
| Want to contribute | Send pull requests to [cashstratum/cashstratum](https://github.com/cashstratum/cashstratum) ([contributing guide](https://github.com/cashstratum/cashstratum/blob/main/CONTRIBUTING.md)) |
| Starred or forked this repository | ⭐ Star and watch [cashstratum/cashstratum](https://github.com/cashstratum/cashstratum) to follow new releases |
| Need the old documentation | It is kept, unmaintained, in [`LEGACY-README.md`](LEGACY-README.md) |

The code here stays online for history and for existing deployments. It will not be updated.

## 🔀 Switch an existing clone

```bash
git remote set-url origin https://github.com/cashstratum/cashstratum.git
git fetch origin --tags
git checkout v1.2.1   # or the latest tag on the releases page
```

CashStratum's history is not a continuation of this repository's commits, so start from a fresh
checkout of a release tag instead of merging. Read the
[changelog](https://github.com/cashstratum/cashstratum/blob/main/CHANGELOG.md) before upgrading a
running pool.

---

<div align="center">

**Bitcoin Cash mining pool software · BCH Stratum server · CKPool fork for Bitcoin Cash ·
BCH solo mining · CashAddr mining pool**

CashStratum descends from [CKPool](https://bitbucket.org/ckolivas/ckpool/) by Con Kolivas and
remains licensed under the [GNU GPL v3](COPYING).

### 👉 [github.com/cashstratum/cashstratum](https://github.com/cashstratum/cashstratum)

</div>
