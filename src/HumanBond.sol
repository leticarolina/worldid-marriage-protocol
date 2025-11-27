// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {VowNFT} from "./VowNFT.sol";
import {TimeToken} from "./TimeToken.sol";
import {MilestoneNFT} from "./MilestoneNFT.sol";

// import {AutomationCompatibleInterface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/AutomationCompatible.sol";

/* ---------------------------- INTERFACE --------------------------- */
/// @notice Interface for the official World ID verifier contract.
interface IWorldID {
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifier,
        uint256[8] calldata proof
    ) external view;
}

/* --------------------------- MAIN CONTRACT -------------------------- */

/**
 * @title HumanBond
 * @notice Main contract managing verified marriages
 * @dev Uses World ID verification to confirm both users are real humans,
 *      then mints static metadata NFTs and TIME ERC-20 token for each verified bond.
 */
contract HumanBond is Ownable {
    error HumanBond__UserAlreadyMarried();
    error HumanBond__InvalidAddress();
    error HumanBond__ProposalAlreadyExists();
    error HumanBond__NotYourMarriage();
    error HumanBond__NoActiveMarriage();
    error HumanBond__CannotProposeToSelf();
    error HumanBond__NotProposedToYou();
    error HumanBond__AlreadyAccepted();
    error HumanBond__NothingToClaim();

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
        uint256 nullifierA; // Nullifiers uniquely represent human identities from World ID
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
    mapping(uint256 => bool) public isHumanMarried; //// Each human (nullifier) can only be in one marriage at a time
    mapping(address => bytes32) public activeMarriageOf; // quick lookup of active marriage ID by user address

    bytes32[] public marriageIds; //So every couple has a unique “marriage fingerprint”

    IWorldID public immutable worldId;
    VowNFT public immutable vowNFT;
    TimeToken public immutable timeToken;
    MilestoneNFT public immutable milestoneNFT;
    // uint256 public immutable externalNullifier;
    uint256 public immutable externalNullifierPropose;
    uint256 public immutable externalNullifierAccept;

    uint256 public constant GROUP_ID = 1;
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

    /* --------------------------- CONSTRUCTOR -------------------------- */
    constructor(
        address _worldId,
        address _VowNFT,
        address _TimeToken,
        address _milestoneNFT,
        uint256 _externalNullifierPropose,
        uint256 _externalNullifierAccept
    ) Ownable(msg.sender) {
        worldId = IWorldID(_worldId);
        vowNFT = VowNFT(_VowNFT);
        timeToken = TimeToken(_TimeToken);
        milestoneNFT = MilestoneNFT(_milestoneNFT);
        externalNullifierPropose = _externalNullifierPropose;
        externalNullifierAccept = _externalNullifierAccept;
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
        if (proposed == address(0)) {
            revert HumanBond__InvalidAddress();
        }
        if (proposed == msg.sender) {
            revert HumanBond__CannotProposeToSelf();
        }

        if (proposals[msg.sender].proposer != address(0)) {
            revert HumanBond__ProposalAlreadyExists();
        }

        // Prevent proposer or proposed user from already being in another bond
        if (isHumanMarried[proposerNullifier]) {
            revert HumanBond__UserAlreadyMarried();
        }

        // Verify proposer is a real human via World ID
        worldId.verifyProof(
            root,
            GROUP_ID,
            uint256(uint160(msg.sender)), // signal = sender address
            proposerNullifier,
            externalNullifierPropose,
            proof
        );

        //Store proposal
        proposals[msg.sender] = Proposal({
            proposer: msg.sender,
            proposed: proposed,
            proposerNullifier: proposerNullifier,
            accepted: false,
            timestamp: block.timestamp
        });

        emit ProposalCreated(msg.sender, proposed);
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
        Proposal storage prop = proposals[proposer]; //retrieving the struct stored in the proposals mapping, previously created in the propose()

        if (
            isHumanMarried[prop.proposerNullifier] ||
            isHumanMarried[acceptorNullifier]
        ) {
            revert HumanBond__UserAlreadyMarried();
        }
        if (prop.proposed != msg.sender) {
            revert HumanBond__NotProposedToYou();
        }

        if (prop.accepted) {
            revert HumanBond__AlreadyAccepted();
        }

        // Verify acceptor is also a real human
        worldId.verifyProof(
            root,
            GROUP_ID,
            uint256(uint160(msg.sender)), // signal = sender address
            acceptorNullifier,
            externalNullifierAccept,
            proof
        );

        bytes32 marriageId = _getMarriageId(proposer, msg.sender);
        if (marriages[marriageId].active) {
            revert HumanBond__UserAlreadyMarried();
        }

        prop.accepted = true;

        isHumanMarried[prop.proposerNullifier] = true;
        isHumanMarried[acceptorNullifier] = true;

        // Record bond data
        marriages[marriageId] = Marriage({
            partnerA: proposer,
            partnerB: msg.sender,
            nullifierA: prop.proposerNullifier,
            nullifierB: acceptorNullifier,
            bondStart: block.timestamp,
            lastClaim: block.timestamp,
            lastMilestoneYear: 0,
            active: true
        });

        // Quick lookup of active marriage ID by user address
        activeMarriageOf[proposer] = marriageId;
        activeMarriageOf[msg.sender] = marriageId;
        // Clear previous proposals — critical for remarrying
        delete proposals[proposer];
        delete proposals[msg.sender];

        marriageIds.push(marriageId);

        // Mint identical NFTs for both
        vowNFT.mintVowNFT(proposer);
        vowNFT.mintVowNFT(msg.sender);

        // Reward both parties with 1 DAY token immediately
        timeToken.mint(proposer, 1 ether);
        timeToken.mint(msg.sender, 1 ether);

        emit ProposalAccepted(proposer, msg.sender);
    }

    /**
     * @notice Allows either partner to dissolve the marriage.
     *         Pending yield is distributed evenly, and both are marked unmarried.
     */
    function divorce(address partner) external {
        bytes32 marriageId = _getMarriageId(msg.sender, partner); //reuses your deterministic pair ID system.
        Marriage storage marriage = marriages[marriageId];

        if (marriage.active == false) {
            revert HumanBond__NoActiveMarriage();
        }

        if (
            msg.sender != marriage.partnerA && msg.sender != marriage.partnerB
        ) {
            revert HumanBond__NotYourMarriage();
        }

        // Claim pending yield (1 token/day shared)
        uint256 reward = _pendingYield(marriageId); //calculates how much DAY they earned since the last claim.
        if (reward > 0) {
            uint256 split = reward / 2;
            timeToken.mint(marriage.partnerA, split);
            timeToken.mint(marriage.partnerB, split);
        }

        // Mark marriage as inactive
        marriage.active = false;
        marriage.lastClaim = block.timestamp;

        // Allow remarriage
        isHumanMarried[marriage.nullifierA] = false;
        isHumanMarried[marriage.nullifierB] = false;
        activeMarriageOf[marriage.partnerA] = 0;
        activeMarriageOf[marriage.partnerB] = 0;

        emit MarriageDissolved(
            marriage.partnerA,
            marriage.partnerB,
            block.timestamp
        );
    }

    /* ---------------------------- YIELD LOGIC --------------------------- */
    function _pendingYield(bytes32 marriageId) internal view returns (uint256) {
        Marriage storage marriage = marriages[marriageId];
        if (!marriage.active) return 0;
        uint256 daysElapsed = (block.timestamp - marriage.lastClaim) /
            1 minutes;
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

    function manualCheckAndMint() external {
        uint256 length = marriageIds.length;
        uint256 maxYear = milestoneNFT.latestYear();

        for (uint256 i = 0; i < length; i++) {
            bytes32 id = marriageIds[i];
            Marriage storage m = marriages[id];

            if (!m.active) continue;

            uint256 yearsTogether = (block.timestamp - m.bondStart) / 2 minutes;

            if (
                yearsTogether > m.lastMilestoneYear && yearsTogether <= maxYear
            ) {
                milestoneNFT.mintMilestone(m.partnerA, yearsTogether);
                milestoneNFT.mintMilestone(m.partnerB, yearsTogether);

                m.lastMilestoneYear = yearsTogether;

                emit AnniversaryAchieved(
                    m.partnerA,
                    m.partnerB,
                    yearsTogether,
                    block.timestamp
                );
            }
        }
    }

    /* --------------------------- HELPER -------------------------- */
    //That makes (A, B) == (B, A)
    function _getMarriageId(
        address a,
        address b
    ) public pure returns (bytes32) {
        return
            a < b
                ? keccak256(abi.encodePacked(a, b))
                : keccak256(abi.encodePacked(b, a));
    }

    /* -------------------------------------------------------------------------- */
    /*                           GETTERS FUNCTIONS                                */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev Get active marriage info for a couple
     */
    function getMarriage(
        address a,
        address b
    ) external view returns (Marriage memory) {
        return marriages[_getMarriageId(a, b)];
    }

    /**
     * @dev Check if two addresses are currently married
     */
    function isMarried(address a, address b) external view returns (bool) {
        return marriages[_getMarriageId(a, b)].active;
    }

    /**
     * @dev Get proposal info for a proposer
     */
    function getProposal(
        address proposer
    ) external view returns (Proposal memory) {
        return proposals[proposer];
    }

    /**
     * @dev Get proposal info for a proposer
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
        // 1) Read proposal (if any)
        Proposal memory p = proposals[user];

        // 2) Read active marriage (O(1))
        bytes32 marriageId = activeMarriageOf[user];

        d.hasProposal = p.proposer != address(0);
        d.timeBalance = timeToken.balanceOf(user);

        if (marriageId != bytes32(0)) {
            Marriage storage m = marriages[marriageId];

            // just guard on active
            if (m.active) {
                d.isMarried = true;
                d.partner = (m.partnerA == user) ? m.partnerB : m.partnerA;
                d.pendingYield = _pendingYield(marriageId);
            } else {
                // mapping might be stale in some edge case, but with your divorce()
                // clearing it this should not happen
                d.isMarried = false;
                d.partner = address(0);
                d.pendingYield = 0;
            }
        } else {
            d.isMarried = false;
            d.partner = address(0);
            d.pendingYield = 0;
        }
    }
}
