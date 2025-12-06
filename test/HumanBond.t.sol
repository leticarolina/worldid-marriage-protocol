// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {HumanBond} from "../src/HumanBond.sol";
import {VowNFT} from "../src/VowNFT.sol";
import {MilestoneNFT} from "../src/MilestoneNFT.sol";
import {TimeToken} from "../src/TimeToken.sol";
import {MarriageIdHelper} from "./utils/MarriageHelper.sol";
import {MockWorldID} from "./utils/MockWorldId.sol";
import {DeployScript} from "../script/Deploy.s.sol";

contract AutomationFlowTest is Test {
    VowNFT vowNFT;
    MilestoneNFT milestoneNFT;
    TimeToken timeToken;
    MockWorldID worldId;
    HumanBond humanBond;
    DeployScript deployer;

    address leticia = makeAddr("leticia");
    address bob = makeAddr("bob");

    // Mock World ID parameters
    uint256 constant ROOT = 1;
    uint256 constant NULLIFIER_PROPOSE = 1111;
    uint256 constant NULLIFIER_ACCEPT = 2222;
    uint256[8] PROOF = [uint256(0), 0, 0, 0, 0, 0, 0, 0];

    function setUp() public {
        // Deploy mock WorldID
        worldId = new MockWorldID();

        // Deploy the other contracts
        vowNFT = new VowNFT();
        milestoneNFT = new MilestoneNFT();
        timeToken = new TimeToken();

        // Deploy HumanBond using the mock
        humanBond = new HumanBond(
            address(worldId),
            address(vowNFT),
            address(timeToken),
            address(milestoneNFT),
            "app_test",
            "propose-bond",
            "accept-bond",
            1 minutes,
            3 minutes
        );

        // Wire up
        milestoneNFT.setHumanBondContract(address(humanBond));
        vowNFT.setHumanBondContract(address(humanBond));
        vowNFT.transferOwnership(address(humanBond));
        timeToken.transferOwnership(address(humanBond));
        milestoneNFT.transferOwnership(address(humanBond));

        // Give ETH
        vm.deal(leticia, 10 ether);
        vm.deal(bob, 10 ether);
    }

    //============================ MODIFIERS ============================//

    modifier marriedCouple() {
        vm.startPrank(leticia);
        humanBond.propose(bob, ROOT, NULLIFIER_PROPOSE, PROOF);
        vm.stopPrank();

        vm.startPrank(bob);
        humanBond.accept(leticia, ROOT, NULLIFIER_ACCEPT, PROOF);
        vm.stopPrank();
        _;
    }

    modifier proposalSent() {
        vm.prank(leticia);
        humanBond.propose(bob, ROOT, NULLIFIER_PROPOSE, PROOF);
        _;
    }

    //test_<unitUnderTest>_<stateOrCondition>_<expectedOutcome/Behaviour>

    //============================ PROPOSAL & ACCEPTANCE TESTS ============================//
    //=====================================================================================//

    function test_propose_reverts_whenProposeToYourself() public {
        vm.prank(leticia);
        vm.expectRevert(HumanBond.HumanBond__CannotProposeToSelf.selector);
        humanBond.propose(leticia, ROOT, NULLIFIER_PROPOSE, PROOF);
    }

    function test_propose_reverts_ifProposeToInvalidAddress() public {
        vm.prank(leticia);
        vm.expectRevert(HumanBond.HumanBond__InvalidAddress.selector);
        humanBond.propose(address(0), ROOT, NULLIFIER_PROPOSE, PROOF);
    }

    function test_propose_reverts_ifAlreadyHasProposalOpen()
        public
        proposalSent
    {
        vm.prank(leticia);
        vm.expectRevert(HumanBond.HumanBond__ProposalAlreadyExists.selector);
        humanBond.propose(address(0x01), NULLIFIER_PROPOSE + 1, 111, PROOF);
    }

    function test_propose_reverts_ifAlreadyMarried() public marriedCouple {
        vm.startPrank(leticia);
        vm.expectRevert(HumanBond.HumanBond__UserAlreadyMarried.selector);
        humanBond.propose(address(0x01), NULLIFIER_PROPOSE + 1, 111, PROOF);

        vm.startPrank(bob);
        vm.expectRevert(HumanBond.HumanBond__UserAlreadyMarried.selector);
        humanBond.propose(address(0x02), NULLIFIER_PROPOSE + 2, 111, PROOF);
    }

    function test_propose_reverts_ifUsingSameNullifier() public proposalSent {
        vm.prank(leticia);
        humanBond.cancelProposal();
        bool usedNullfier = humanBond.usedNullifier(
            humanBond.externalNullifierPropose(),
            NULLIFIER_PROPOSE
        );
        assertEq(usedNullfier, true);

        vm.expectRevert(HumanBond.HumanBond__InvalidNullifier.selector);
        humanBond.propose(address(0x01), ROOT, NULLIFIER_PROPOSE, PROOF);
    }

    function test_propose_sucessfully_storeProposal() public proposalSent {
        uint256 timeStamp = block.timestamp;
        HumanBond.Proposal memory letisProposal = humanBond.getProposal(
            leticia
        );
        assertEq(letisProposal.proposer, leticia);
        assertEq(letisProposal.proposed, bob);
        assertEq(letisProposal.proposerNullifier, NULLIFIER_PROPOSE);
        assertEq(letisProposal.accepted, false);
        assertEq(letisProposal.timestamp, timeStamp);
    }

    function test_propose_emits_bothEvents() public {
        // Expect ProposalCreated
        vm.expectEmit(address(humanBond));
        emit HumanBond.ProposalCreated(leticia, bob);

        // Expect NullifierUsed
        vm.expectEmit(address(humanBond));
        emit HumanBond.NullifierUsed(
            humanBond.externalNullifierPropose(),
            NULLIFIER_PROPOSE,
            leticia
        );
        vm.prank(leticia);
        humanBond.propose(bob, ROOT, NULLIFIER_PROPOSE, PROOF);
    }

    //============================ ACCEPTANCE TESTS =======================================//
    //=====================================================================================//

    function test_accept_reverts_ifNotCorrectPartnerAccept()
        public
        proposalSent
    {
        vm.expectRevert(HumanBond.HumanBond__NotProposedToYou.selector);
        humanBond.accept(leticia, ROOT, NULLIFIER_ACCEPT, PROOF);
    }

    // function test_accept_reverts_ifNullifierAlreadyUsed() public marriedCouple {
    //     // recreates a new proposal because accept() deletes it
    //     vm.prank(leticia);
    //     humanBond.propose(bob, ROOT, 1002, PROOF);

    //     // bob tries to accept using SAME nullifier 2001 → should revert
    //     vm.prank(bob);
    //     vm.expectRevert(HumanBond.HumanBond__InvalidNullifier.selector);
    //     humanBond.accept(leticia, ROOT, NULLIFIER_ACCEPT, PROOF);
    // }

    function test_accept_getMarriageId_recordsMarriageIdSymmetryAndPushToArray()
        public
        marriedCouple
    {
        MarriageIdHelper helper = new MarriageIdHelper();

        bytes32 id1 = helper.exposed_getMarriageId(leticia, bob);
        bytes32 id2 = helper.exposed_getMarriageId(bob, leticia);
        bytes32 recordedMarriage = humanBond.marriageIds(0);

        assertEq(id1, id2, "Marriage IDs should be symmetric");
        assertEq(recordedMarriage, id1);
    }

    function test_accept_changeAcceptToTrue() public marriedCouple {
        bool currentStatus = humanBond.isMarried(leticia, bob);

        assertEq(currentStatus, true);
    }

    function test_accept_deletes_allPreviousProposals() public proposalSent {
        vm.startPrank(bob);
        humanBond.propose(address(0x01), ROOT, NULLIFIER_PROPOSE + 1, PROOF);
        humanBond.accept(leticia, ROOT, NULLIFIER_ACCEPT, PROOF);
        vm.stopPrank();
        HumanBond.Proposal memory bobsProposal = humanBond.getProposal(bob);
        assertEq(bobsProposal.proposer, address(0));
        assertEq(bobsProposal.proposed, address(0));
    }

    function test_accpet_MintsVowNFTandSendTokens() public marriedCouple {
        assertEq(vowNFT.ownerOf(1), leticia);
        assertEq(vowNFT.ownerOf(2), bob);
        assertEq(timeToken.balanceOf(leticia), 1 ether);
        assertEq(timeToken.balanceOf(bob), 1 ether);
    }

    //======================================= YIELD TESTS ===============================//
    //===================================================================================//
    function test_pendingYield_recordsBalanceCorrectly() public marriedCouple {
        // warp minutes (100 TIME)
        skip(block.timestamp + 100 minutes);
        uint256 expectedBalance = humanBond.getPendingYield(leticia, bob);
        assertEq(expectedBalance, 100 ether);
    }

    function test_claimYield_splitsTokensEvenlyAndResetsCounter()
        public
        marriedCouple
    {
        skip(block.timestamp + 10 minutes);

        vm.prank(leticia);
        humanBond.claimYield(bob);

        // both receive 5 TIME token + 1 initial mint
        assertEq(timeToken.balanceOf(leticia), 1 ether + 5 ether);
        assertEq(timeToken.balanceOf(bob), 1 ether + 5 ether);

        // pending yield resets to 0
        uint256 pendingAfterClaim = humanBond.getPendingYield(leticia, bob);
        assertEq(pendingAfterClaim, 0);
    }

    //==================================  MILESTONES NFTS ===============================//
    //===================================================================================//
    function test_checkAndMintMilestone_reverts_ifNoActiveMarriage() public {
        // Leticia is NOT married
        vm.prank(leticia);
        vm.expectRevert(HumanBond.HumanBond__NoActiveMarriage.selector);
        humanBond.checkAndMintMilestone(bob);
    }

    function test_checkAndMintMilestone_reverts_ifYearNotReached()
        public
        marriedCouple
    {
        // marriage just started
        vm.prank(leticia);
        vm.expectRevert(HumanBond.HumanBond__NothingToClaim.selector);
        humanBond.checkAndMintMilestone(bob);
    }

    function test_milestone_reverts_ifYearExceedsMax() public marriedCouple {
        uint256 max = milestoneNFT.latestYear();

        // warp to year = 5
        skip((max + 1));

        vm.prank(leticia);
        vm.expectRevert(HumanBond.HumanBond__NothingToClaim.selector);
        humanBond.checkAndMintMilestone(bob);
    }

    // function test_milestone_mintsCorrectlyForBothPartners()
    //     public
    //     marriedCouple
    // {
    //     skip(3 minutes); // yearTogether = 1
    //     uint256 tokenA_before = milestoneNFT.balanceOf(leticia);
    //     uint256 tokenB_before = milestoneNFT.balanceOf(bob);

    //     vm.prank(leticia);
    //     humanBond.checkAndMintMilestone(bob);

    //     assertEq(milestoneNFT.balanceOf(leticia), tokenA_before + 1);
    //     assertEq(milestoneNFT.balanceOf(bob), tokenB_before + 1);
    // }

    // function test_milestone_updatesLastMilestoneYear() public marriedCouple {
    //     skip(2 minutes); // yearTogether = 1

    //     vm.prank(leticia);
    //     humanBond.checkAndMintMilestone(bob);

    //     // fetch record
    //     bytes32 id = humanBond._getMarriageId(leticia, bob);
    //     (, , , , , uint256 lastYear, bool active) = humanBond.marriages(id);

    //     assertEq(lastYear, 1);
    //     assertTrue(active);
    // }

    //============================ DIVORCE TESTS ============================//
    // function test__DivorceWorks() public {
    //     // marry
    //     vm.startPrank(leticia);
    //     humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     humanBond.accept(leticia, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     // divorce
    //     vm.startPrank(leticia);
    //     humanBond.divorce(bob);
    //     vm.stopPrank();

    //     bytes32 id = humanBond._getMarriageId(leticia, bob);
    //     (, , , , , , , bool active) = humanBond.marriages(id);

    //     assertFalse(active, "Marriage should be inactive after divorce");
    //     // assertFalse(humanBond.isHumanMarried(1111), "Nullifier A not freed");
    //     // assertFalse(humanBond.isHumanMarried(2222), "Nullifier B not freed");
    // }

    // function test__DivorceDistributesPendingYield() public {
    //     // marry
    //     vm.startPrank(leticia);
    //     humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     humanBond.accept(leticia, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     // warp 10 days → 10 TIME yield
    //     vm.warp(block.timestamp + 10 minutes);

    //     vm.startPrank(leticia);
    //     humanBond.divorce(bob);
    //     vm.stopPrank();

    //     // pending = 10 → split = 5 each
    //     assertEq(timeToken.balanceOf(leticia), 1 ether + 5 ether);
    //     assertEq(timeToken.balanceOf(bob), 1 ether + 5 ether);
    // }

    // function test__DivorceTwiceFails() public {
    //     // marry
    //     vm.startPrank(leticia);
    //     humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     humanBond.accept(leticia, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     vm.startPrank(leticia);
    //     humanBond.divorce(bob);

    //     vm.expectRevert(HumanBond.HumanBond__NoActiveMarriage.selector);
    //     humanBond.divorce(bob);
    //     vm.stopPrank();
    // }

    // function test__ClaimYieldAfterDivorceFails() public {
    //     // marry
    //     vm.startPrank(leticia);
    //     humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     humanBond.accept(leticia, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     // divorce
    //     vm.startPrank(leticia);
    //     humanBond.divorce(bob);
    //     vm.stopPrank();

    //     vm.startPrank(leticia);
    //     vm.expectRevert(HumanBond.HumanBond__NoActiveMarriage.selector);
    //     humanBond.claimYield(bob);
    //     vm.stopPrank();
    // }

    // function test__RemarryAfterDivorce() public {
    //     // ----------- FIRST MARRIAGE -----------
    //     vm.startPrank(leticia);
    //     humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     humanBond.accept(leticia, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     // Divorce
    //     vm.startPrank(leticia);
    //     humanBond.divorce(bob);
    //     vm.stopPrank();

    //     // Both nullifiers must be free
    //     // assertFalse(humanBond.isHumanMarried(1111));
    //     // assertFalse(humanBond.isHumanMarried(2222));

    //     // ----------- SECOND MARRIAGE -----------
    //     vm.startPrank(leticia);
    //     humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     humanBond.accept(leticia, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     // Marriage must be active again
    //     bytes32 id = humanBond._getMarriageId(leticia, bob);
    //     (, , , , , , , bool active) = humanBond.marriages(id);
    //     assertTrue(active, "Should be active after remarrying");

    //     // Both must have received new VowNFTs
    //     assertEq(vowNFT.ownerOf(3), leticia);
    //     assertEq(vowNFT.ownerOf(4), bob);

    //     // New initial TIME token allocation should be present
    //     assertEq(timeToken.balanceOf(leticia), 1 ether + 1 ether); // first mint + second mint
    //     assertEq(timeToken.balanceOf(bob), 1 ether + 1 ether);
    // }

    //=============== GETTERS TESTS ===============//
    // function test__GetMarriageView() public {
    //     // marry
    //     vm.startPrank(leticia);
    //     humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     humanBond.accept(leticia, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     // warp 3 days
    //     vm.warp(block.timestamp + 3 minutes);

    //     HumanBond.MarriageView memory v = humanBond.getMarriageView(
    //         leticia,
    //         bob
    //     );

    //     assertEq(v.partnerA, leticia);
    //     assertEq(v.partnerB, bob);
    //     assertEq(v.nullifierA, 1111);
    //     assertEq(v.nullifierB, 2222);
    //     assertEq(v.active, true);
    //     assertEq(v.pendingYield, 3 ether);
    // }

    // function test__UserDashboard() public {
    //     // proposal
    //     vm.startPrank(leticia);
    //     humanBond.propose(bob, 1, 1111, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     // BEFORE ACCEPT — Alice has proposal, not married
    //     {
    //         HumanBond.UserDashboard memory d1 = humanBond.getUserDashboard(
    //             leticia
    //         );
    //         assertTrue(d1.hasProposal);
    //         assertFalse(d1.isMarried);
    //         assertEq(d1.partner, address(0));
    //     }

    //     // accept
    //     vm.startPrank(bob);
    //     humanBond.accept(leticia, 1, 2222, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    //     vm.stopPrank();

    //     // warp 5 days → 5 tokens pending
    //     vm.warp(block.timestamp + 5 minutes);

    //     // AFTER ACCEPT — married, partner detected
    //     HumanBond.UserDashboard memory d2 = humanBond.getUserDashboard(leticia);

    //     assertTrue(d2.isMarried);
    //     assertFalse(d2.hasProposal);
    //     assertEq(d2.partner, bob);
    //     assertEq(d2.pendingYield, 5 ether);
    //     assertEq(d2.timeBalance, 1 ether); // initial mint
    // }
}
