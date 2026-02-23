// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {VendingMachineCore} from "./VendingMachineCore.sol";

/// @title VendingMachineOps
/// @notice Operational functions for payment handling and state management
library VendingMachineOps {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    /// @dev Internal function to handle payment for a purchase.
    /// @param paymentToken The token used for payment (address(0) for ETH).
    /// @param totalCost The total cost of the purchase.
    /// @param fundsRecipient The address to receive the funds.
    function handlePayment(
        address paymentToken,
        uint256 totalCost,
        address fundsRecipient
    ) internal {
        if (paymentToken == address(0)) {
            if (msg.value < totalCost) revert VendingMachineCore.InsufficientPayment();
            fundsRecipient.safeTransferETH(totalCost);
            if (msg.value > totalCost) {
                msg.sender.safeTransferETH(msg.value - totalCost);
            }
        } else {
            if (msg.value != 0) revert VendingMachineCore.InvalidPaymentToken();
            SafeTransferLib.safeTransferFrom(
                paymentToken,
                msg.sender,
                fundsRecipient,
                totalCost
            );
        }
    }

    /// @dev Updates purchase state using versioned tracking
    /// @param tokenId The token ID purchased
    /// @param quantity The quantity purchased
    /// @param saleConfigs Mapping of sale configurations
    /// @param versionedUserPurchases Mapping of versioned user purchases
    /// @param purchaser The address making the purchase
    function updatePurchaseStateVersioned(
        uint256 tokenId,
        uint32 quantity,
        mapping(uint256 => VendingMachineCore.SaleConfig) storage saleConfigs,
        mapping(bytes32 => uint32) storage versionedUserPurchases,
        address purchaser
    ) internal {
        VendingMachineCore.SaleConfig storage config = saleConfigs[tokenId];
        config.totalSold = (uint256(config.totalSold) + quantity).toUint32();
        
        bytes32 key = VendingMachineCore.getVersionedPurchaseKey(
            tokenId,
            config.saleVersion,
            purchaser
        );
        
        versionedUserPurchases[key] = (uint256(versionedUserPurchases[key]) + quantity).toUint32();
    }

    /// @dev Internal function to add a token ID to the active sales array if not already present.
    /// @param tokenId The token ID to add.
    /// @param activeSaleTokenIds Array of active sale token IDs
    /// @param isInActiveArray Mapping to check if token is in array
    /// @param tokenIdToArrayIndex Mapping of token ID to array index
    function addToActiveArray(
        uint256 tokenId,
        uint256[] storage activeSaleTokenIds,
        mapping(uint256 => bool) storage isInActiveArray,
        mapping(uint256 => uint256) storage tokenIdToArrayIndex
    ) internal {
        if (!isInActiveArray[tokenId]) {
            uint256 index = activeSaleTokenIds.length;
            activeSaleTokenIds.push(tokenId);
            isInActiveArray[tokenId] = true;
            tokenIdToArrayIndex[tokenId] = index;
        }
    }

    /// @dev Internal function to remove a token ID from the active sales array.
    /// @param tokenId The token ID to remove.
    /// @param activeSaleTokenIds Array of active sale token IDs
    /// @param isInActiveArray Mapping to check if token is in array
    /// @param tokenIdToArrayIndex Mapping of token ID to array index
    function removeFromActiveArray(
        uint256 tokenId,
        uint256[] storage activeSaleTokenIds,
        mapping(uint256 => bool) storage isInActiveArray,
        mapping(uint256 => uint256) storage tokenIdToArrayIndex
    ) internal {
        if (isInActiveArray[tokenId]) {
            uint256 indexToRemove = tokenIdToArrayIndex[tokenId];
            uint256 lastIndex = activeSaleTokenIds.length - 1;
            if (indexToRemove != lastIndex) {
                uint256 lastTokenId = activeSaleTokenIds[lastIndex];
                activeSaleTokenIds[indexToRemove] = lastTokenId;
                tokenIdToArrayIndex[lastTokenId] = indexToRemove;
            }
            activeSaleTokenIds.pop();
            delete tokenIdToArrayIndex[tokenId];
            isInActiveArray[tokenId] = false;
        }
    }
}

