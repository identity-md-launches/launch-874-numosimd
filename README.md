# NumosIMD (NUMOS)

NumosIMD is an immutable ERC-20 token. Its constructor mints the entire supply once to `msg.sender`.

| Deployment field | Value |
| --- | --- |
| Contract | `src/NumosIMD.sol:NumosIMD` |
| Name | `NumosIMD` |
| Symbol | `NUMOS` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; encoded bytes `0x`) |
| Constructor native value | `0` |
| Initial recipient | Immediate constructor caller |
| Additional application contracts | None |

## Build and test

Install Foundry and make Solidity **0.8.26** available in Foundry's compiler cache. Then run:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies are vendored as ordinary files under `lib/`; no dependency installation,
submodules, RPC, keys, or environment variables are needed to build or test. Once the pinned compiler
and Foundry are available, these commands work without network access. The configuration pins Cancun
EVM semantics, optimizer settings (enabled, 200 runs), and `bytecode_hash = "none"`. FFI and filesystem
cheatcode permissions are disabled.

The tests cover constructor issuance and its event, CREATE2 factory deployment, exact launch-style
transfers, balances, allowances, events, zero and self transfers, maximum allowances, invalid addresses,
insufficient balances and approvals, revocation, rollback after failure, and unsupported administrative
calls. Four fuzz tests run 512 cases each. A stateful invariant runs 128 sequences of 64 calls, comparing
balances and allowances to an independent accounting model and checking supply conservation.

## Behavior and assumptions

- The requested supply means one billion **whole tokens**, scaled by `10^18` for onchain accounting.
- Transfers deliver exactly the requested amount. There are no taxes, rebases, fees, or exemptions.
- The deployed contract exposes no mint, burn, owner, pause, blacklist, seizure, or upgrade functions.
  Minting is reachable only during construction. Holders control their own balances and approvals;
  the deployer has no special rights after receiving the initial supply.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert with OpenZeppelin's
  ERC-20 custom errors on failure. Failed calls leave balances and allowances unchanged.
- Zero-value transfers between nonzero addresses and self transfers are supported. Transfers to the
  zero address and approvals to the zero spender revert. Sending to an unusable nonzero address,
  including the token contract itself, can lock tokens permanently; there is no recovery function.
- `approve` replaces the previous allowance. Finite allowances decrease on `transferFrom`;
  `type(uint256).max` is unlimited and does not decrease. Even a holder calling `transferFrom` on
  itself needs an allowance for a positive amount; direct `transfer` needs none.
- Explicit approvals emit `Approval`. Transfers, including zero-value transfers, emit `Transfer`.
  This OpenZeppelin version does not emit an additional `Approval` when spending an allowance;
  consumers should read `allowance` for its current value.
- There are no callbacks, external calls, time dependencies, oracles, chain addresses, or maintenance
  functions in the token. Ordinary native-currency payments revert. Assets forcibly delivered to it
  cannot be recovered through this contract.

## Deployment handoff

The deployer should compile and deploy the exact contract and settings above. Inspect local artifacts
without accessing a wallet or submitting a transaction:

```sh
forge inspect src/NumosIMD.sol:NumosIMD abi
forge inspect src/NumosIMD.sol:NumosIMD bytecode
forge inspect src/NumosIMD.sol:NumosIMD deployedBytecode
```

Direct deployment gives the full supply to the deploying account. Deployment by a factory through
CREATE or CREATE2 gives it to that factory, **not** the transaction origin or requester. The factory
must be able to transfer its holdings. No initializer, follow-up mint, constructor address, or token
administrator needs configuration. For CREATE2, the launch operator chooses the salt; there are no
constructor arguments to append to the creation bytecode.

For an IdentityMD custom-token launch, the manifest's token fields are the values in the table above,
with `constructorArgs: []`, and the application-contract list is empty. The external launch factory
handles the ten-percent swarm allocation and subsequent pool/requester distributions. The token does
not allocate shares on its own. Pool parameters, the paired asset, initial capitalization, requester
recipient, and chain were not supplied and remain the launch operator's responsibility; this project
does not invent a launch manifest or deploy launch infrastructure.

Before release, the operator must select and verify the target chain supports the configured EVM,
confirm the intended factory or account will receive the supply, verify deployed bytecode and source
with the pinned compiler/settings, and check metadata, total supply, the mint event, and resulting
distribution balances. The project assumes a standard Cancun-compatible EVM and does not provide a
zkSync-specific compiler or deployment workflow. No chain or live integration was verified here.

## Operational responsibilities and review

The initial recipient is responsible for custody and distribution of the one-billion-token supply.
Holders are responsible for recipient addresses and approvals: spenders can spend approved funds.
Prefer bounded approvals and revoke unused allowances. Replacing a live nonzero allowance has the
usual ERC-20 transaction-ordering race; zeroing it first and waiting for confirmation reduces this
risk but cannot undo spending already confirmed.

There is no administrator to rotate, upgrade to schedule, pause switch, or ongoing keeper task.
Defects cannot be repaired in place. Release review, deployment, source verification, pool setup,
distribution, and monitoring belong to the launch operator. No transactions were broadcast and no
wallet credentials are part of this project.

Local checks include compilation, unit/fuzz tests, stateful invariants, and runtime opcode checks for
DELEGATECALL, CALLCODE, and SELFDESTRUCT. The launch-style transfer test checks token accounting with
stand-in addresses; it does not run the network's real Uniswap v4 seed/swap integration. The supplied
protected integration test requires launch infrastructure and manifest/environment inputs not
included in this assignment. That complete integration remains for the independent launch verifier.
Slither and Mythril were not run. Passing tests is not an audit; an independent adversarial review
remains a release responsibility.

## Dependencies

The production contract inherits the unmodified OpenZeppelin Contracts **v5.0.2** ERC-20. Only its
required Solidity source closure and MIT license are vendored. Tests use the complete `src/` tree of
forge-std **v1.9.6**, with both upstream license files. Exact source commits and downloaded archive
hashes are recorded in [`lib/dependencies.json`](lib/dependencies.json). No upstream deployment
scripts, package managers, or repository metadata are needed.
