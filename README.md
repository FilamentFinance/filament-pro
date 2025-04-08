# Filament Finance Pro V2

Enhancing Perpetual Trading on a Decentralised Exchange with Precision and Agility. Discover Filament, where advanced, proven mechanisms fuse with unparalleled market adaptability for a superior trading experience.

## Setup

This Repo is have been developed in Hardhat with some Foundry features used.

1. Git Clone
```
git clone https://github.com/FilamentFinance/Filament-v1.git
```
- Switch to `audit` branch
- Duplicate `.env.example` and rename it to `.env`
- Add PRIVATE_KEY
- Add SEITRACE_API_KEY as `0e0cb6ed-15c4-44fd-bc37-2740ed4f0104` 

2. Install Dependencies

```
yarn --frozen-lock-file
```
3. Build

```
yarn hardhat compile
```
4. Test

```
yarn hardhat test

```

5. Coverage

```
yarn hardhat coverage

6. Deploy Contracts

```
yarn hardhat run deploy/deploy.js --network seiTestnet
```
