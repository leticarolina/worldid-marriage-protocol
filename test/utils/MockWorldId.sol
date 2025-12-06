// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWorldID} from "../../lib/world-id-contracts/src/interfaces/IWorldID.sol";

contract MockWorldID is IWorldID {
    bool public shouldRevert;

    function setShouldRevert(bool _value) external {
        shouldRevert = _value;
    }

    function verifyProof(
        uint256,
        uint256,
        uint256,
        uint256,
        uint256[8] calldata
    ) external view override {
        if (shouldRevert) {
            revert("MockWorldID: invalid proof");
        }
    }
}
