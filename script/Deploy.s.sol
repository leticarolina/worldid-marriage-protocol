// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {VowNFT} from "../src/VowNFT.sol";
import {IWorldID, HumanBond} from "../src/HumanBond.sol";
import {MilestoneNFT} from "../src/MilestoneNFT.sol";
import {TimeToken} from "../src/TimeToken.sol";

/// @title Deploy Script for HumanBond Protocol
/// @notice Deploys TimeToken, VowNFT, MilestoneNFT and HumanBond logic contract, sets up linkage, and prints addresses.
contract DeployScript is Script {
    struct DeployedContracts {
        VowNFT vowNFT;
        MilestoneNFT milestoneNFT;
        TimeToken timeToken;
        HumanBond humanBond;
    }

    function run() external returns (DeployedContracts memory deployed) {
        vm.startBroadcast();

        // Deploy contract and tokens
        VowNFT vowNFT = new VowNFT();
        MilestoneNFT milestoneNFT = new MilestoneNFT();
        TimeToken timeToken = new TimeToken();
        address WORLD_ID_ROUTER_SEPOLIA = 0x469449f251692E0779667583026b5A1E99512157;

        //Set milestones metadata URIs BEFORE ownership transfer
        milestoneNFT.setMilestoneURI(
            1,
            "ipfs://QmPAVmWBuJnNgrGrAp34CqTa13VfKkEZkZak8d6E4MJio8"
        );
        milestoneNFT.setMilestoneURI(
            2,
            "ipfs://QmPTuKXg64EaeyreUFe4PJ1istspMd4G2oe2ArRYrtBGYn"
        );
        milestoneNFT.setMilestoneURI(
            3,
            "ipfs://Qma32oBrwNNQVR3KS14RHqt3QhgYMsGKabQv4jusdtgsKN"
        );
        milestoneNFT.setMilestoneURI(
            4,
            "ipfs://QmSw9ixqCVc7VPQzDdX1ZCdWWJwAfLHRdJsi831PsC94uh"
        );
        milestoneNFT.freezeMilestones();

        // HumanBond parameters
        string memory appId = "app_test"; // for local dev, replace with real appId on testnet
        string memory actionPropose = "propose-bond";
        string memory actionAccept = "accept-bond";

        //Deploy HumanBond main contract
        HumanBond humanBond = new HumanBond(
            WORLD_ID_ROUTER_SEPOLIA, // replace w/ chosen network WORLD ID ROUTER
            address(vowNFT),
            address(timeToken),
            address(milestoneNFT),
            appId,
            actionPropose,
            actionAccept,
            1 minutes,
            3 minutes
        );

        //Link contracts
        milestoneNFT.setHumanBondContract(address(humanBond)); //Link MilestoneNFT to HumanBond
        vowNFT.setHumanBondContract(address(humanBond));

        // Step 4: Set contracts authorization
        vowNFT.transferOwnership(address(humanBond));
        timeToken.transferOwnership(address(humanBond));
        milestoneNFT.transferOwnership(address(humanBond));

        vm.stopBroadcast();

        // Logs
        console.log("VowNFT deployed at:", address(vowNFT));
        console.log("MilestoneNFT deployed at:", address(milestoneNFT));
        console.log("HumanBond deployed at:", address(humanBond));
        console.log("Time Token deployed at:", address(timeToken));
        console.log("Deployment complete!");

        deployed = DeployedContracts({
            vowNFT: vowNFT,
            milestoneNFT: milestoneNFT,
            timeToken: timeToken,
            humanBond: humanBond
        });
    }
}
