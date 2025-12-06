// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";

/**
 * @title VowNFT
 * @dev ERC721 token representing a verified human bond.
 *      Uses a single static IPFS metadata URI for all minted tokens.
 */
contract VowNFT is ERC721, Ownable {
    error VowNFT__UnauthorizedMinter();
    error VowNFT__TransfersDisabled();
    uint256 public tokenId;
    string public metadataTokenURI;
    address public humanBondContract; //authorized minter address

    modifier onlyHumanBond() {
        _onlyHumanBond();
        _;
    }

    function _onlyHumanBond() public view {
        if (msg.sender != humanBondContract) {
            revert VowNFT__UnauthorizedMinter();
        }
    }

    constructor() ERC721("Vows", "VOW") Ownable(msg.sender) {
        tokenId = 0;
        metadataTokenURI = "ipfs://QmaZoH31LuX5imBGXQE6oxJtpHim3z8mKE3naMu6XFFYuB";
    }

    /// @notice Set the HumanBond contract address
    //lets the owner (the deployer) set which contract is allowed to mint
    function setHumanBondContract(address contractAddress) external onlyOwner {
        humanBondContract = contractAddress;
    }

    /// @notice Mint a Bond NFT to a given address.
    //only HumanBond contract can mint
    function mintVowNFT(address to) external onlyHumanBond returns (uint256) {
        tokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /// @notice Returns the static IPFS metadata URI for all tokens.
    function tokenURI(
        uint256 idOfToken
    ) public view override returns (string memory) {
        _requireOwned(idOfToken);
        return metadataTokenURI;
    }

    /* -------------------------------------------------------------------------- */
    /*                             SOULBOUND OVERRIDES                             */
    /* -------------------------------------------------------------------------- */
    function _update(
        address to,
        uint256 tokenIdd,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenIdd);

        if (from != address(0) && to != from) {
            revert VowNFT__TransfersDisabled();
        }

        return super._update(to, tokenIdd, auth);
    }
}
