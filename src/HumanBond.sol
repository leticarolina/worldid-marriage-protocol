// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {VowNFT} from "./VowNFT.sol";
import {TimeToken} from "./TimeToken.sol";
import {MilestoneNFT} from "./MilestoneNFT.sol";
import {ByteHasher} from "./helpers/ByteHasher.sol";
import {IWorldID} from "../lib/world-id-contracts/src/interfaces/IWorldID.sol";

/* --------------------------- MAIN CONTRACT -------------------------- */
/**
 * @title HumanBond
 * @author Leticia Azevedo (@letiweb3)
 * @notice Main contract managing verified marriages
 * @dev Uses World ID verification to confirm both users are real humans,
 *      then mints NFTs and TIME ERC-20 token for each verified bond.
 */
contract HumanBond is Ownable {
    using ByteHasher for bytes;

    error HumanBond__UserAlreadyMarried();
    error HumanBond__InvalidAddress();
    error HumanBond__ProposalAlreadyExists();
    error HumanBond__NotYourMarriage();
    error HumanBond__NoActiveMarriage();
    error HumanBond__CannotProposeToSelf();
    error HumanBond__NotProposedToYou();
    error HumanBond__AlreadyAccepted();
    error HumanBond__NothingToClaim();
    error HumanBond__InvalidNullifier();

    /* ----------------------------- STRUCTS ----------------------------- */
    //Represents a pending bond request:
    struct Proposal {
        address proposer;
        address proposed;
        uint256 proposerNullifier;
        bool accepted;
        uint256 timestamp;
    }

    //Represents an active relationship between two verified humans
    struct Marriage {
        address partnerA;
        address partnerB;
        uint256 nullifierA; //represent human identities from World ID
        uint256 nullifierB;
        uint256 bondStart;
        uint256 lastClaim;
        uint256 lastMilestoneYear;
        bool active;
    }

    // View struct for external read-only access
    struct MarriageView {
        address partnerA;
        address partnerB;
        uint256 nullifierA;
        uint256 nullifierB;
        uint256 bondStart;
        uint256 lastClaim;
        uint256 lastMilestoneYear;
        bool active;
        uint256 pendingYield;
    }

    // View struct for user dashboard
    struct UserDashboard {
        bool isMarried;
        bool hasProposal;
        address partner;
        uint256 pendingYield;
        uint256 timeBalance;
    }

    /* --------------------------- STATE VARS --------------------------- */
    mapping(address => Proposal) public proposals;
    mapping(bytes32 => Marriage) public marriages;
    mapping(address => bytes32) public activeMarriageOf; // quick lookup of active marriage ID by user address
    // nullifier + externalNullifier combination prevents double-signalling for a particular action.
    mapping(uint256 => mapping(uint256 => bool)) public usedNullifier; //key usedNullifier by externalNullifier.

    bytes32[] public marriageIds; //So every couple has a unique “marriage fingerprint”

    IWorldID public immutable worldId;
    VowNFT public immutable vowNFT;
    TimeToken public immutable timeToken;
    MilestoneNFT public immutable milestoneNFT;
    uint256 public immutable externalNullifierPropose;
    uint256 public immutable externalNullifierAccept;

    // uint256 public constant GROUP_ID = 1;
    uint256 public immutable DAY; // for tests (1 day = 1 minutes)
    uint256 public immutable YEAR; // for tests (1 year = 3 minutes)

    /* ----------------------------- EVENTS ----------------------------- */
    event ProposalCreated(address indexed proposer, address indexed proposed);
    event ProposalAccepted(address indexed partnerA, address indexed partnerB);
    event YieldClaimed(
        address indexed partnerA,
        address indexed partnerB,
        uint256 rewardEach
    );
    event AnniversaryAchieved(
        address indexed partnerA,
        address indexed partnerB,
        uint256 year,
        uint256 timestamp
    );
    event MarriageDissolved(
        address indexed partnerA,
        address indexed partnerB,
        uint256 timestamp
    );
    event ProposalCancelled(address indexed proposer, address indexed proposed);
    event NullifierUsed(
        uint256 externalNullifier,
        uint256 nullifier,
        address user
    );

    /* --------------------------- CONSTRUCTOR -------------------------- */
    constructor(
        address _worldIdRouter,
        address _VowNFT,
        address _TimeToken,
        address _milestoneNFT,
        string memory _appId, // NEW
        string memory _actionPropose, // NEW
        string memory _actionAccept, // NEW
        uint256 _day, // for tests
        uint256 _year // for tests
    ) Ownable(msg.sender) {
        worldId = IWorldID(_worldIdRouter);
        vowNFT = VowNFT(_VowNFT);
        timeToken = TimeToken(_TimeToken);
        milestoneNFT = MilestoneNFT(_milestoneNFT);

        // Compute external nullifiers exactly as World ID expects, define action domain for proofs
        externalNullifierPropose = abi
            .encodePacked(
                abi.encodePacked(_appId).hashToField(),
                _actionPropose
            )
            .hashToField();

        externalNullifierAccept = abi
            .encodePacked(abi.encodePacked(_appId).hashToField(), _actionAccept)
            .hashToField();
        DAY = _day;
        YEAR = _year;
    }

    /* ---------------------------- FUNCTIONS --------------------------- */

    /// @notice Propose a bond to another verified human using World ID.
    /// @param proposed The address of the person being proposed to.
    /// @param root The World ID root from the proof.
    /// @param proposerNullifier The unique nullifier preventing proof re-use.
    /// @param proof The zero-knowledge proof array.
    function propose(
        address proposed,
        uint256 root,
        uint256 proposerNullifier,
        uint256[8] calldata proof
    ) external {
        uint256 signalHash = abi.encodePacked(msg.sender).hashToField(); //prove msg.sender is signer

        if (proposed == address(0)) {
            revert HumanBond__InvalidAddress();
        }
        if (proposed == msg.sender) {
            revert HumanBond__CannotProposeToSelf();
        }
        if (proposals[msg.sender].proposer != address(0)) {
            revert HumanBond__ProposalAlreadyExists();
        }
        if (
            activeMarriageOf[msg.sender] != bytes32(0) ||
            activeMarriageOf[proposed] != bytes32(0)
        ) {
            revert HumanBond__UserAlreadyMarried();
        }
        if (usedNullifier[externalNullifierPropose][proposerNullifier]) {
            revert HumanBond__InvalidNullifier();
        }

        // Verify proposer is a real human via World ID
        worldId.verifyProof(
            root,
            signalHash,
            proposerNullifier,
            externalNullifierPropose,
            proof
        );

        usedNullifier[externalNullifierPropose][proposerNullifier] = true; // mark nullifier as used

        //Store proposal
        proposals[msg.sender] = Proposal({
            proposer: msg.sender,
            proposed: proposed,
            proposerNullifier: proposerNullifier,
            accepted: false,
            timestamp: block.timestamp
        });

        emit ProposalCreated(msg.sender, proposed);
        emit NullifierUsed(
            externalNullifierPropose,
            proposerNullifier,
            msg.sender
        );
    }

    /// @notice Accept an existing proposal, verify humanity, and mint NFTs + ERC-20.
    /// @param proposer The address of the original proposer.
    /// @param root The World ID root from the proof.
    /// @param acceptorNullifier The unique nullifier preventing proof re-use.
    /// @param proof The zero-knowledge proof array.
    function accept(
        address proposer,
        uint256 root,
        uint256 acceptorNullifier,
        uint256[8] calldata proof
    ) external {
        Proposal storage proposalOfProposer = proposals[proposer]; //retrieving the struct stored in the proposals mapping, previously created in the propose()
        uint256 signalHash = abi.encodePacked(msg.sender).hashToField();

        if (proposalOfProposer.proposed != msg.sender) {
            revert HumanBond__NotProposedToYou();
        }
        if (usedNullifier[externalNullifierAccept][acceptorNullifier]) {
            revert HumanBond__InvalidNullifier();
        } //not reaching, UserAlreadyMarried in propose fires first
        if (
            activeMarriageOf[proposer] != bytes32(0) ||
            activeMarriageOf[msg.sender] != bytes32(0)
        ) {
            revert HumanBond__UserAlreadyMarried();
        } //not reaching, propose function reverts before

        // Verify acceptor is also a real human
        worldId.verifyProof(
            root,
            // GROUP_ID,
            signalHash, // signal = sender address
            acceptorNullifier,
            externalNullifierAccept,
            proof
        );

        // Create marriage ID
        bytes32 marriageId = _getMarriageId(proposer, msg.sender);
        if (marriages[marriageId].active) {
            revert HumanBond__UserAlreadyMarried();
        }

        proposalOfProposer.accepted = true;
        usedNullifier[externalNullifierAccept][acceptorNullifier] = true;

        // Record bond data
        marriages[marriageId] = Marriage({
            partnerA: proposer,
            partnerB: msg.sender,
            nullifierA: proposalOfProposer.proposerNullifier,
            nullifierB: acceptorNullifier,
            bondStart: block.timestamp,
            lastClaim: block.timestamp,
            lastMilestoneYear: 0,
            active: true
        });

        activeMarriageOf[proposer] = marriageId; //active marriage ID by user address
        activeMarriageOf[msg.sender] = marriageId;

        delete proposals[proposer]; // Clear previous proposals — for remarrying
        delete proposals[msg.sender];

        marriageIds.push(marriageId);

        // Mint identical NFTs for both
        vowNFT.mintVowNFT(proposer);
        vowNFT.mintVowNFT(msg.sender);

        // Reward both parties with 1 TOKEN immediately
        timeToken.mint(proposer, 1 ether);
        timeToken.mint(msg.sender, 1 ether);

        emit ProposalAccepted(proposer, msg.sender);
        emit NullifierUsed(
            externalNullifierAccept,
            acceptorNullifier,
            msg.sender
        );
    }

    /**
     * @notice Allows either partner to dissolve the marriage.
     *         Pending yield is distributed evenly, and both are marked unmarried.
     */
    function divorce(address partner) external {
        bytes32 marriageId = _getMarriageId(msg.sender, partner); //reuses deterministic pair ID system.
        Marriage storage marriage = marriages[marriageId];

        if (marriage.active == false) {
            revert HumanBond__NoActiveMarriage();
        }
        if (
            msg.sender != marriage.partnerA && msg.sender != marriage.partnerB
        ) {
            revert HumanBond__NotYourMarriage();
        }

        uint256 reward = _pendingYield(marriageId); //calculates how much tokens they earned since the last claim.
        // Claim pending yield (1 token/day shared) before divorce
        if (reward > 0) {
            uint256 split = reward / 2;
            timeToken.mint(marriage.partnerA, split);
            timeToken.mint(marriage.partnerB, split);
        }

        // Mark marriage as inactive
        marriage.active = false;
        marriage.lastClaim = block.timestamp;

        // Allow remarriage
        activeMarriageOf[marriage.partnerA] = bytes32(0);
        activeMarriageOf[marriage.partnerB] = bytes32(0);

        emit MarriageDissolved(
            marriage.partnerA,
            marriage.partnerB,
            block.timestamp
        );
    }

    /* ---------------------------- YIELD LOGIC --------------------------- */
    function _pendingYield(bytes32 marriageId) internal view returns (uint256) {
        Marriage storage marriage = marriages[marriageId];
        if (!marriage.active) revert HumanBond__NoActiveMarriage();
        uint256 daysElapsed = (block.timestamp - marriage.lastClaim) / DAY;
        return daysElapsed * 1 ether; // 1 DAY token per full day
    }

    function claimYield(address partner) external {
        bytes32 marriageId = _getMarriageId(msg.sender, partner);
        Marriage storage marriage = marriages[marriageId];
        if (!marriage.active) revert HumanBond__NoActiveMarriage();

        uint256 reward = _pendingYield(marriageId);
        if (reward == 0) {
            revert HumanBond__NothingToClaim();
        }

        uint256 split = reward / 2;

        timeToken.mint(marriage.partnerA, split);
        timeToken.mint(marriage.partnerB, split);

        marriage.lastClaim = block.timestamp;
        emit YieldClaimed(marriage.partnerA, marriage.partnerB, split);
    }

    /* -------------------------------------------------------------------------- */
    /*                           NFT MILESTONE LOGIC                              */
    /* -------------------------------------------------------------------------- */

    function checkAndMintMilestone(address partner) external {
        bytes32 id = _getMarriageId(msg.sender, partner);
        Marriage storage m = marriages[id];

        if (!m.active) {
            revert HumanBond__NoActiveMarriage();
        }
        if (msg.sender != m.partnerA && msg.sender != m.partnerB) {
            revert HumanBond__NotYourMarriage(); // Ensure caller is one of the partners
        }

        uint256 yearsTogether = (block.timestamp - m.bondStart) / YEAR;
        uint256 maxYear = milestoneNFT.latestYear();

        // No new year achieved
        if (
            yearsTogether <= m.lastMilestoneYear ||
            yearsTogether == 0 ||
            yearsTogether > maxYear
        ) {
            revert HumanBond__NothingToClaim();
        }

        // Mint for both partners
        milestoneNFT.mintMilestone(m.partnerA, yearsTogether);
        milestoneNFT.mintMilestone(m.partnerB, yearsTogether);

        // Update state
        m.lastMilestoneYear = yearsTogether;

        emit AnniversaryAchieved(
            m.partnerA,
            m.partnerB,
            yearsTogether,
            block.timestamp
        );
    }

    /* --------------------------- HELPER -------------------------- */
    //That makes (A, B) == (B, A)
    function _getMarriageId(
        address a,
        address b
    ) internal pure returns (bytes32) {
        return
            a < b
                ? keccak256(abi.encodePacked(a, b))
                : keccak256(abi.encodePacked(b, a));
    }

    /* --------------------------- PROPOSALS -------------------------- */
    function cancelProposal() external {
        Proposal memory proposalOfProposer = proposals[msg.sender];
        if (proposalOfProposer.proposer == address(0)) {
            revert HumanBond__InvalidAddress();
        }
        delete proposals[msg.sender];
        emit ProposalCancelled(msg.sender, proposalOfProposer.proposed);
    }

    /* -------------------------------------------------------------------------- */
    /*                           GETTERS FUNCTIONS                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev Get active marriage struct with all info for a couple bond
     */
    function getMarriage(
        address a,
        address b
    ) external view returns (Marriage memory) {
        return marriages[_getMarriageId(a, b)];
    }

    /**
     * @dev Check if two addresses are currently married based on the marriage struct, returns bool
     */
    function isMarried(address a, address b) external view returns (bool) {
        return marriages[_getMarriageId(a, b)].active;
    }

    /**
     * @dev Get proposal info from proposer
     */
    function getProposal(
        address proposer
    ) external view returns (Proposal memory) {
        return proposals[proposer];
    }

    /**
     * @dev Get if a user has a pending proposal
     */
    function hasPendingProposal(address proposer) external view returns (bool) {
        return proposals[proposer].proposer != address(0);
    }

    /**
     * @dev Get the current pending yield for a couple
     */
    function getPendingYield(
        address a,
        address b
    ) external view returns (uint256) {
        return _pendingYield(_getMarriageId(a, b));
    }

    /**
     * @dev Get the current milestone year for a couple
     */
    function getCurrentMilestoneYear(
        address a,
        address b
    ) external view returns (uint256) {
        return marriages[_getMarriageId(a, b)].lastMilestoneYear;
    }

    /**
     * @dev Get the bond start timestamp for a couple
     */
    function getBondStart(
        address a,
        address b
    ) external view returns (uint256) {
        return marriages[_getMarriageId(a, b)].bondStart;
    }

    /**
     * @dev Get a read-only view struct for a couple's marriage
     */
    function getMarriageView(
        address a,
        address b
    ) external view returns (MarriageView memory v) {
        bytes32 id = _getMarriageId(a, b);
        Marriage memory m = marriages[id];

        v = MarriageView({
            partnerA: m.partnerA,
            partnerB: m.partnerB,
            nullifierA: m.nullifierA,
            nullifierB: m.nullifierB,
            bondStart: m.bondStart,
            lastClaim: m.lastClaim,
            lastMilestoneYear: m.lastMilestoneYear,
            active: m.active,
            pendingYield: _pendingYield(id)
        });
    }

    function getUserDashboard(
        address user
    ) external view returns (UserDashboard memory d) {
        //Load the user’s proposal (could be empty)
        Proposal memory p = proposals[user];
        //Read active marriage
        bytes32 marriageId = activeMarriageOf[user];

        d.hasProposal = p.proposer != address(0);
        d.timeBalance = timeToken.balanceOf(user); // load user’s TIME balance

        if (marriageId == bytes32(0)) {
            // User is NOT married
            d.isMarried = false;
            d.partner = address(0);
            d.pendingYield = 0;
            return d;
        }

        // User IS married
        Marriage storage m = marriages[marriageId];
        d.isMarried = m.active;
        d.partner = (m.partnerA == user) ? m.partnerB : m.partnerA;
        d.pendingYield = _pendingYield(marriageId);
    }
}
