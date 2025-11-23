// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";

/// @title VendingMachineCore
/// @notice Core definitions, errors, types, and validation logic for the vending machine
library VendingMachineCore {
    using LibBitmap for LibBitmap.Bitmap;

    /// @dev Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();
    /// @dev Thrown when a zero amount is provided where a positive value is required
    error ZeroAmount();
    /// @dev Thrown when array parameters have mismatched lengths
    error ArrayLengthMismatch();
    /// @dev Thrown when attempting to purchase from an inactive sale
    error SaleNotActive();
    /// @dev Thrown when referencing a sale configuration that doesn't exist
    error SaleNotFound();
    /// @dev Thrown when payment amount is less than required
    error InsufficientPayment();
    /// @dev Thrown when purchase would exceed maximum supply limit
    error ExceedsMaxSupply();
    /// @dev Thrown when purchase would exceed per-address limit
    error ExceedsMaxPerAddress();
    /// @dev Thrown when using wrong payment token type (ETH vs ERC20)
    error InvalidPaymentToken();
    /// @dev Thrown when sale time range is invalid (start >= end)
    error InvalidTimeRange();
    /// @dev Thrown when contract dependencies are not properly initialized
    error NotInitialized();
    /// @dev Thrown when contract doesn't hold sufficient inventory for the operation
    error InsufficientInventory();
    /// @dev Thrown when duplicate token IDs are found in batch operations
    error DuplicateTokenId();
    /// @dev Thrown when attempting to send tokens from unauthorized contract
    error UnauthorizedTokenTransfer();
    /// @dev Thrown when withdrawal would leave insufficient inventory for active sales
    error ActiveSaleInventoryRequired();
    /// @dev Thrown when attempting to update a sale parameter to an invalid value
    error InvalidParam();
    /// @dev Thrown when batch size exceeds maximum
    error BatchTooLarge();
    /// @dev Thrown when arithmetic would overflow
    error ArithmeticOverflow();
    /// @dev Thrown when trying to reconfigure an active sale
    error SaleMustBeInactive();

    /// @dev Configuration struct for individual token sales, including pricing, timing, supply limits, and status.
    struct SaleConfig {
        uint128 price;
        uint64 startTime;
        uint64 endTime;
        uint32 maxSupply;
        uint32 maxPerAddress;
        uint32 totalSold;
        address paymentToken;
        bool active;
        uint64 saleVersion;
    }

    /// @dev Maximum allowed batch size to prevent gas griefing
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @dev Generates versioned key for user purchase tracking
    /// @param tokenId The token ID
    /// @param saleVersion The sale version
    /// @param user The user address
    /// @return The hashed key for the mapping
    function getVersionedPurchaseKey(
        uint256 tokenId,
        uint64 saleVersion,
        address user
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenId, saleVersion, user));
    }

    /// @dev Checks for duplicate token IDs in an array
    /// @param tokenIds Array of token IDs to check
    function checkForDuplicates(uint256[] calldata tokenIds) internal pure {
        uint256 length = tokenIds.length;
        for (uint256 i; i < length; ) {
            for (uint256 j = i + 1; j < length; ) {
                if (tokenIds[i] == tokenIds[j]) {
                    revert DuplicateTokenId();
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Internal validation using versioned user purchases
    /// @param tokenId The token ID being purchased
    /// @param quantity The quantity being purchased
    /// @param activeSales Bitmap of active sales
    /// @param saleConfigs Mapping of sale configurations
    /// @param versionedUserPurchases Mapping of versioned user purchases
    /// @param ksItems The ERC1155 contract
    function validatePurchaseVersioned(
        uint256 tokenId,
        uint32 quantity,
        LibBitmap.Bitmap storage activeSales,
        mapping(uint256 => SaleConfig) storage saleConfigs,
        mapping(bytes32 => uint32) storage versionedUserPurchases,
        IERC1155 ksItems,
        address purchaser
    ) internal view {
        if (!activeSales.get(tokenId)) revert SaleNotActive();
        SaleConfig memory config = saleConfigs[tokenId];
        if (!config.active) revert SaleNotActive();
        uint256 currentTime = block.timestamp;
        if (currentTime < config.startTime || currentTime > config.endTime) {
            revert SaleNotActive();
        }
        if (config.totalSold + quantity > config.maxSupply) {
            revert ExceedsMaxSupply();
        }
        if (ksItems.balanceOf(address(this), tokenId) < quantity) {
            revert InsufficientInventory();
        }
        if (config.maxPerAddress > 0) {
            bytes32 key = getVersionedPurchaseKey(
                tokenId,
                config.saleVersion,
                purchaser
            );
            if (versionedUserPurchases[key] + quantity > config.maxPerAddress) {
                revert ExceedsMaxPerAddress();
            }
        }
    }

    /// @dev Internal function to check if a sale is live based on config and time.
    /// @param config The sale configuration.
    /// @param currentTime The current timestamp.
    /// @return True if the sale is live.
    function isLive(
        SaleConfig memory config,
        uint256 currentTime
    ) internal pure returns (bool) {
        return
            config.active &&
            currentTime >= config.startTime &&
            currentTime <= config.endTime &&
            config.totalSold < config.maxSupply;
    }
}
