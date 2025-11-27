// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {HumanBond, IWorldID} from "../src/HumanBond.sol";
import {VowNFT} from "../src/VowNFT.sol";
import {MilestoneNFT} from "../src/MilestoneNFT.sol";
import {TimeToken} from "../src/TimeToken.sol";
import {MarriageIdHelper} from "./utils/MarriageHelper.sol";

// Dummy verifier (same used in deploy)
contract DummyWorldID is IWorldID {
    function verifyProof(uint256, uint256, uint256, uint256, uint256, uint256[8] calldata) external pure override {}
}

contract AutomationFlowTest is Test {
    VowNFT vowNFT;
    MilestoneNFT milestoneNFT;
    TimeToken timeToken;
    DummyWorldID worldId;
    HumanBond humanBond;

    address alice = address(0xA1);
    address bob = address(0xB1);

    function setUp() public {
        // Deploy base components
        worldId = new DummyWorldID();
        vowNFT = new VowNFT();
        milestoneNFT = new MilestoneNFT();
        timeToken = new TimeToken();

        // Set milestone URIs (required or mint will revert)
        milestoneNFT.setMilestoneURI(1, "ipfs://QmPAVmWBuJnNgrGrAp34CqTa13VfKkEZkZak8d6E4MJio8");
        milestoneNFT.setMilestoneURI(2, "ipfs://QmPTuKXg64EaeyreUFe4PJ1istspMd4G2oe2ArRYrtBGYn");

        // Deploy HumanBond
        humanBond =
            new HumanBond(address(worldId), address(vowNFT), address(timeToken), address(milestoneNFT), 12345, 67890);

        // Link contracts
        milestoneNFT.setHumanBondContract(address(humanBond));
        vowNFT.setHumanBondContract(address(humanBond));

        // Transfer ownership so HumanBond can mint
        milestoneNFT.transferOwnership(address(humanBond));
        timeToken.transferOwnership(address(humanBond));
        vowNFT.transferOwnership(address(humanBond));

        // Give ETH so things don't revert
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test__CannotProposeToSelf() public {
        vm.startPrank(alice);
        vm.expectRevert();
        humanBond.propose(alice, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();
    }

    function test__proposal_CannotProposeTwice() public {
        vm.startPrank(alice);

        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);

        vm.expectRevert(); // expecting double proposal revert
        humanBond.propose(address(0xB5), 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);

        vm.stopPrank();
    }

    function test__OnlyProposedPartnerCanAccept() public {
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        address intruder = address(0xDEAD);

        vm.startPrank(intruder);
        vm.expectRevert();
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();
    }

    function test__MarriageIdSymmetry() public {
        // Deploy helper
        MarriageIdHelper helper = new MarriageIdHelper();

        bytes32 id1 = helper.exposed_getMarriageId(alice, bob);
        bytes32 id2 = helper.exposed_getMarriageId(bob, alice);

        assertEq(id1, id2, "Marriage IDs should be symmetric");
    }

    function test__VowNFTMintedOnAccept() public {
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        assertEq(vowNFT.ownerOf(1), alice);
        assertEq(vowNFT.ownerOf(2), bob);
    }

    function test__InitialTimeTokenMintOnAccept() public {
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        assertEq(timeToken.balanceOf(alice), 1 ether);
        assertEq(timeToken.balanceOf(bob), 1 ether);
    }

    function test__TimeWithdrawalSplitEvenly() public {
        // marry
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // warp minutes (100 TIME)
        vm.warp(block.timestamp + 100 minutes);

        // withdraw yield — but the correct method is claimYield(partner)
        vm.startPrank(alice);
        humanBond.claimYield(bob);
        vm.stopPrank();

        // both should get 50 tokens each
        assertEq(timeToken.balanceOf(alice), 51 ether);
        assertEq(timeToken.balanceOf(bob), 51 ether);
    }

    function test__ClaimYieldResetsCounter() public {
        // marry
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // warp 1 day
        vm.warp(block.timestamp + 1 minutes);

        // Correct ordering: caller is alice, partner is bob
        vm.startPrank(alice);
        humanBond.claimYield(bob);
        vm.stopPrank();

        // both receive 0.5 DAY token + 1 initial mint
        assertEq(timeToken.balanceOf(alice), 1 ether + 0.5 ether);
        assertEq(timeToken.balanceOf(bob), 1 ether + 0.5 ether);

        // warp another day
        vm.warp(block.timestamp + 1 minutes);

        // claim again
        vm.startPrank(bob);
        humanBond.claimYield(alice);
        vm.stopPrank();

        assertEq(timeToken.balanceOf(alice), 2 ether);
        assertEq(timeToken.balanceOf(bob), 2 ether);
    }

    function test__OnlyHumanBondCanMintMilestone() public {
        vm.expectRevert();
        milestoneNFT.mintMilestone(alice, 1);
    }

    //============================ MILESTONE NFT  ============================//
    function testManualCheckAndMint() public {
        address A = address(0x1);
        address B = address(0x2);

        uint256 root = 1;
        uint256 nullA = 10;
        uint256 nullB = 20;
        uint256[8] memory proof;

        // A proposes
        vm.startPrank(A);
        humanBond.propose(B, root, nullA, proof);
        vm.stopPrank();

        // B accepts
        vm.startPrank(B);
        humanBond.accept(A, root, nullB, proof);
        vm.stopPrank();

        // warp forward to satisfy 1 "year" (2 minutes)
        vm.warp(block.timestamp + 2 minutes + 1);

        // call manual function
        humanBond.manualCheckAndMint();

        // check milestone minted (ERC721)
        assertEq(milestoneNFT.balanceOf(A), 1, "A should have 1 milestone NFT");
        assertEq(milestoneNFT.balanceOf(B), 1, "B should have 1 milestone NFT");

        // verify state updated
        HumanBond.Marriage memory m = humanBond.getMarriage(A, B);

        assertEq(m.lastMilestoneYear, 1, "Milestone year should update");
    }

    //============================ DIVORCE TESTS ============================//
    function test__DivorceWorks() public {
        // marry
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // divorce
        vm.startPrank(alice);
        humanBond.divorce(bob);
        vm.stopPrank();

        bytes32 id = humanBond._getMarriageId(alice, bob);
        (,,,,,,, bool active) = humanBond.marriages(id);

        assertFalse(active, "Marriage should be inactive after divorce");
        assertFalse(humanBond.isHumanMarried(1111), "Nullifier A not freed");
        assertFalse(humanBond.isHumanMarried(2222), "Nullifier B not freed");
    }

    function test__DivorceDistributesPendingYield() public {
        // marry
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // warp 10 days → 10 TIME yield
        vm.warp(block.timestamp + 10 minutes);

        vm.startPrank(alice);
        humanBond.divorce(bob);
        vm.stopPrank();

        // pending = 10 → split = 5 each
        assertEq(timeToken.balanceOf(alice), 1 ether + 5 ether);
        assertEq(timeToken.balanceOf(bob), 1 ether + 5 ether);
    }

    function test__DivorceTwiceFails() public {
        // marry
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(alice);
        humanBond.divorce(bob);

        vm.expectRevert(HumanBond.HumanBond__NoActiveMarriage.selector);
        humanBond.divorce(bob);
        vm.stopPrank();
    }

    function test__ClaimYieldAfterDivorceFails() public {
        // marry
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // divorce
        vm.startPrank(alice);
        humanBond.divorce(bob);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(HumanBond.HumanBond__NoActiveMarriage.selector);
        humanBond.claimYield(bob);
        vm.stopPrank();
    }

    function test__RemarryAfterDivorce() public {
        // ----------- FIRST MARRIAGE -----------
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // Divorce
        vm.startPrank(alice);
        humanBond.divorce(bob);
        vm.stopPrank();

        // Both nullifiers must be free
        assertFalse(humanBond.isHumanMarried(1111));
        assertFalse(humanBond.isHumanMarried(2222));

        // ----------- SECOND MARRIAGE -----------
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // Marriage must be active again
        bytes32 id = humanBond._getMarriageId(alice, bob);
        (,,,,,,, bool active) = humanBond.marriages(id);
        assertTrue(active, "Should be active after remarrying");

        // Both must have received new VowNFTs
        assertEq(vowNFT.ownerOf(3), alice);
        assertEq(vowNFT.ownerOf(4), bob);

        // New initial TIME token allocation should be present
        assertEq(timeToken.balanceOf(alice), 1 ether + 1 ether); // first mint + second mint
        assertEq(timeToken.balanceOf(bob), 1 ether + 1 ether);
    }

    //=============== GETTERS TESTS ===============//
    function test__GetMarriageView() public {
        // marry
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // warp 3 days
        vm.warp(block.timestamp + 3 minutes);

        HumanBond.MarriageView memory v = humanBond.getMarriageView(alice, bob);

        assertEq(v.partnerA, alice);
        assertEq(v.partnerB, bob);
        assertEq(v.nullifierA, 1111);
        assertEq(v.nullifierB, 2222);
        assertEq(v.active, true);
        assertEq(v.pendingYield, 3 ether);
    }

    function test__UserDashboard() public {
        // proposal
        vm.startPrank(alice);
        humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // BEFORE ACCEPT — Alice has proposal, not married
        {
            HumanBond.UserDashboard memory d1 = humanBond.getUserDashboard(alice);
            assertTrue(d1.hasProposal);
            assertFalse(d1.isMarried);
            assertEq(d1.partner, address(0));
        }

        // accept
        vm.startPrank(bob);
        humanBond.accept(alice, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
        vm.stopPrank();

        // warp 5 days → 5 tokens pending
        vm.warp(block.timestamp + 5 minutes);

        // AFTER ACCEPT — married, partner detected
        HumanBond.UserDashboard memory d2 = humanBond.getUserDashboard(alice);

        assertTrue(d2.isMarried);
        assertFalse(d2.hasProposal);
        assertEq(d2.partner, bob);
        assertEq(d2.pendingYield, 5 ether);
        assertEq(d2.timeBalance, 1 ether); // initial mint
    }
}
