# 💍 HumanBond Protocol — V2

On-chain marriage, yield, milestones & relationship-proof infrastructure.
A clean refactor of the ETHGlobal Buenos Aires 2025 hackaton project “marriageDAO”.

## Table of Contents

1. [Introduction](#introduction)
2. [Smart Contracts](#smart-contracts)
3. [Protocol Overview](#protocol-overview)
4. [Author](#written-and-refactored-by)

## Introduction

HumanBond enables two verified humans (via World ID) to form a cryptographically provable bond on-chain. Turning getting married into a few clicks, minting a commemorative dynamic metadata NFT upon marriage.

A bond is both:

Legal-fiction marriage primitive, and two-person DAO with treasury, governance, and shared yield.

## Smart Contracts

### World Chain Mainnet

- **Human Bond (Core Engine)**: [0x6494daa4e693F748Eb0a16041ECfCEd51392bB13](https://worldscan.org/address/0x6494daa4e693F748Eb0a16041ECfCEd51392bB13)
- **Vow Dynamic Onchain NFT**: [0xa1650cc531c2780fb8c006f4b8d314018f7f9ac9](https://worldscan.org/address/0xa1650cc531c2780fb8c006f4b8d314018f7f9ac9)
- **Milestone Upgradeable NFT**:
[0x0a2759241d0cb610e3e61db351813ddf8a52f14c](https://worldscan.org/address/0x0a2759241d0cb610e3e61db351813ddf8a52f14c)
- **TIME Token**:
[0x261f6d89491cbadff7813303363a514f4b226a82](https://worldscan.org/address/0x261f6d89491cbadff7813303363a514f4b226a82)

## Protocol Overview

Core Lifecycle and Main Functions:

- **1. Proposal**

propose(address proposed, root, nullifier, proof)

Verified via World ID;
Stores outgoing proposal;
Registers incoming proposal;
Prevents spam & multi-proposals;

- **2. Acceptance**

accept(proposer, root, nullifier, proof)

Verifies both humans;
Creates deterministic marriage ID;
Mints Vow NFTs with dynamic personalized data for the couple;
Mints 1 TIME token to each partner;
Deletes all proposals;
Activates marriage;

- **3. Daily Yield**

Every day together → 1 TIME token accumulated (shared).

claimYield(partner)
Splits the accumulated TIME tokens 50/50;

- **4. Milestones (“Memories”)**

manualCheckAndMint(partner)

Mints yearly anniversary NFT(s);
Supports catching up on missed years;

- **5. Divorce**

divorce(partner)

Instant Divorce, simplifying and reducing costs of the divorcing process;
Automatically mints and withdraw shared pending yield;
Marks marriage inactive;
Allows both users to send/accept proposals and marry again;

## Refactoring from Hackaton to v2

V2 is a smart-contract refactor focusing on:

### Clean architecture

- Gas-efficient proposal tracking
- Incoming proposals indexing
- Outgoing proposal tracking
- Proposal cancellation
- Deterministic marriage IDs upon marriage
- Direct UI-ready getter functions
- Simple dashboard call for married users
- Zero-knowledge proof integration via World ID (propose + accept)
- Improved NFT + Token logic
- Dynamic Vow NFT for both partners
- Yearly Milestones system with auto-catch-up minting
- TIME ERC-20 token as “bond yield”
- Ownership model as EOAs remain owners
- HumanBond contract authorized to mint
- All contracts deployed & verified on World Chain Mainnet

## Written and refactored by

- Leticia Azevedo: Smart Contracts Developer (Brasil)
