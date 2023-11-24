# LimitlessFi

Decentralized perpetual protocol.

## Table of Contents

- [Introduction](#introduction)
- [Getting Started](#getting-started)

  - [Installation](#installation)

- [Usage](#usage)
- [License](#license)

## Introduction

LimitlessFi is a decentralized permissionless perpetual protocol built in Solidity. It allows traders to speculate on the price movements of ETH without a need for an expiration date and without having them to actually buy the token, while enabling traders to employ leverage.

## Getting Started

There are two entry points to the system:

- `Vault.sol`
- `Market.sol`

`Vault.sol` allows users to deposit liquidity into the protocol, which will be available for traders to borrow. Traders can open a Long or Short position with up to 15x of leverage in `Market.sol`. Traders pay a borrowing fee, which is a 10% of the position to be charged over the course of the year. Borrowing fees are claimed from traders and deposited into `Vault.sol` to later be claimed by depositors. Borrowing fees accrue to every depositor based on time spent in the market and their pro rata share of the pool.

If trader's position exceeds max leverage it can be liquidated by anyone. The position is liquidated by invoking `liquidate` function in `Market.sol`, liquidator receive a liquidation fee, which is a percentage of user's collateral.

### Installation

`git clone https://github.com/kazantseff/LimitlessFi`.
Run `foundryup` and `forge install` to install dependencies.

## Usage

Will later be deployed to Goerli Testnet.

## License

MIT
