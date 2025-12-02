# Nivra Court
Nivra Court is a decentralized arbitration protocol for Sui network's smart contracts. **[WIP]**

## Nivra Architecture

![Design](/design.png) 

`CourtRegistry` acts as the entry point for deploying and managing courts within the nivra protocol.
<br><br>
`Court` handles staking, disputes, and appeals. Nivsters stake NVR tokens to participate as jurors. When a dispute or appeal is submitted, nivsters are randomly selected, with higher staked amounts increasing the probability of being chosen.
<br><br>
`Dispute` follows a four-stage process to determine the outcome of a problem statement:

1. Evidence period - The parties involved may each submit up to three pieces of evidence to support their case.
2. Voting period - Nivsters cast confidential votes in favor of one party. All votes are encrypted using SEAL.
3. Appeal period - Votes are decrypted, and either party may appeal the result, initiating a new round with additional Nivsters.
4. Reward period - The final results are recorded, and rewards/penalties are distributed to participants.

`Evidence` contains an explanation and, optionally, a BlobID referencing a Walrus file. The file may be encrypted using SEAL so that it is accessible only to the Nivsters assigned to the case.

## Installation

### Prerequisites:
1. [**Sui**](https://move-book.com/before-we-begin/install-sui) + [**MVR**](https://move-book.com/before-we-begin/install-move-registry-cli)
    - Setup a sui cli account and environments. [quickstart guide](https://github.com/NivraLabs/Sui-QSG)

### Deploy the smart contracts:

Navigate to the `packages/nivra` folder and run:
```
sui client publish --with-unpublished-dependencies
```

