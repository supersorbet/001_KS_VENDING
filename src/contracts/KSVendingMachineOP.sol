// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVendingMachine} from "../interfaces/IVendingMachine.sol";
import {VendingMachineCore} from "../libraries/VendingMachineCore.sol";
import {VendingMachineOps} from "../libraries/VendingMachineOps.sol";

/// @title KSItemVendingMachine - SECURITY PATCHED VERSION
/// @notice Direct sales contract for KSItems with configurable payment options and active sales array
contract KSVendingMachineOP_Patched is Ownable, ReentrancyGuard, IERC1155Receiver, IVendingMachine {
    using SafeTransferLib for address;
    using LibBitmap for LibBitmap.Bitmap;

    /// @notice The ERC1155 contract address for the items being vended.
    IERC1155 public ksItems;
    /// @notice The address where funds from sales are sent.
    address public fundsRecipient;
    /// @notice Mapping of token IDs to their sale configurations.
    mapping(uint256 => VendingMachineCore.SaleConfig) public saleConfigs;
    /// @notice Mapping of versioned purchase keys to amounts
    /// @dev Key is keccak256(abi.encodePacked(tokenId, saleVersion, userAddress))
    mapping(bytes32 => uint32) public versionedUserPurchases;

    /// @dev Internal bitmap for gas-efficient active sales checks.
    LibBitmap.Bitmap private _activeSales;

    /// @notice Array of token IDs for currently active sales.
    uint256[] public activeSaleTokenIds;
    /// @dev Internal mapping to check if a token ID is in the active array.
    mapping(uint256 => bool) private _isInActiveArray;
    /// @dev Internal mapping of token ID to its index in the active array for efficient removal.
    mapping(uint256 => uint256) private _tokenIdToArrayIndex;
    /// @notice Flag to pause all purchases
    bool public paused;

    /// @dev Modifier to ensure critical addresses are initialized
    modifier whenInitialized() {
        if (address(ksItems) == address(0) || fundsRecipient == address(0)) {
            revert VendingMachineCore.NotInitialized();
        }
        _;
    }

    /// @dev Modifier to prevent actions when the contract is paused.
    modifier whenNotPaused() {
        if (paused) revert VendingMachineCore.SaleNotActive();
        _;
    }

    /// @dev Initializes the contract with the deployer as the owner.
    constructor() {
        _initializeOwner(msg.sender);
    }

    /// @notice Purchases a specified quantity of a single token.
    /// @dev Validates the purchase, handles payment, updates state, and transfers tokens. Reentrancy protected.
    /// @param tokenId The ID of the token to purchase.
    /// @param quantity The number of tokens to purchase.
    function purchase(
        uint256 tokenId,
        uint32 quantity
    ) external payable nonReentrant whenNotPaused whenInitialized {
        if (quantity == 0) revert VendingMachineCore.ZeroAmount();
        VendingMachineCore.validatePurchaseVersioned(
            tokenId,
            quantity,
            _activeSales,
            saleConfigs,
            versionedUserPurchases,
            ksItems,
            msg.sender
        );

        VendingMachineCore.SaleConfig storage config = saleConfigs[tokenId];
        uint256 totalCost = uint256(config.price) * quantity;
        
        VendingMachineOps.handlePayment(config.paymentToken, totalCost, fundsRecipient);
        VendingMachineOps.updatePurchaseStateVersioned(
            tokenId,
            quantity,
            saleConfigs,
            versionedUserPurchases,
            msg.sender
        );
        
        ksItems.safeTransferFrom(address(this), msg.sender, tokenId, quantity, "");
        
        emit Purchase(msg.sender, tokenId, quantity, config.price, config.paymentToken);
    }

    /// @notice Purchases multiple tokens in a batch.
    /// @dev Validates each purchase, handles payments, updates state, and batch transfers tokens. Reentrancy protected.
    /// @param tokenIds Array of token IDs to purchase.
    /// @param quantities Array of quantities corresponding to each token ID.
    function purchaseBatch(
        uint256[] calldata tokenIds,
        uint32[] calldata quantities
    ) external payable nonReentrant whenNotPaused whenInitialized {
        uint256 length = tokenIds.length;
        if (length != quantities.length) revert VendingMachineCore.ArrayLengthMismatch();
        if (length > VendingMachineCore.MAX_BATCH_SIZE) revert VendingMachineCore.BatchTooLarge();
        VendingMachineCore.checkForDuplicates(tokenIds);
        
        uint256 totalETHCost;
        for (uint256 i; i < length; ) {
            if (quantities[i] == 0) revert VendingMachineCore.ZeroAmount();
            
            VendingMachineCore.validatePurchaseVersioned(
                tokenIds[i],
                quantities[i],
                _activeSales,
                saleConfigs,
                versionedUserPurchases,
                ksItems,
                msg.sender
            );
            
            VendingMachineCore.SaleConfig memory config = saleConfigs[tokenIds[i]];
            if (config.paymentToken == address(0)) {
                totalETHCost += uint256(config.price) * quantities[i];
            }
            unchecked {
                ++i;
            }
        }
        
        if (totalETHCost > 0 && msg.value < totalETHCost) {
            revert VendingMachineCore.InsufficientPayment();
        }

        uint256[] memory batchTokenIds = new uint256[](length);
        uint256[] memory batchQuantities = new uint256[](length);
        
        for (uint256 i; i < length; ) {
            uint256 tokenId = tokenIds[i];
            uint32 quantity = quantities[i];
            VendingMachineCore.SaleConfig storage config = saleConfigs[tokenId];
            
            if (config.paymentToken != address(0)) {
                uint256 cost = uint256(config.price) * quantity;
                SafeTransferLib.safeTransferFrom(
                    config.paymentToken,
                    msg.sender,
                    fundsRecipient,
                    cost
                );
            }
            
            VendingMachineOps.updatePurchaseStateVersioned(
                tokenId,
                quantity,
                saleConfigs,
                versionedUserPurchases,
                msg.sender
            );
            
            batchTokenIds[i] = tokenId;
            batchQuantities[i] = quantity;

            emit Purchase(msg.sender, tokenId, quantity, config.price, config.paymentToken);
            unchecked {
                ++i;
            }
        }
        
        ksItems.safeBatchTransferFrom(
            address(this),
            msg.sender,
            batchTokenIds,
            batchQuantities,
            ""
        );
        
        if (totalETHCost > 0) {
            fundsRecipient.safeTransferETH(totalETHCost);
            if (msg.value > totalETHCost) {
                msg.sender.safeTransferETH(msg.value - totalETHCost);
            }
        }
    }

    /// @notice Optimized batch purchase that aggregates ERC20 payments by token for efficiency. [experimental]
    /// @dev Validates purchases, aggregates payments (one transfer per unique ERC20), updates state, and batch transfers tokens. Reentrancy protected.
    /// @param tokenIds Array of token IDs to purchase.
    /// @param quantities Array of quantities corresponding to each token ID.
    function purchaseBatchOptimized(
        uint256[] calldata tokenIds,
        uint32[] calldata quantities
    ) external payable nonReentrant whenNotPaused whenInitialized {
        uint256 length = tokenIds.length;
        if (length != quantities.length) revert VendingMachineCore.ArrayLengthMismatch();
        if (length > VendingMachineCore.MAX_BATCH_SIZE) revert VendingMachineCore.BatchTooLarge();
        VendingMachineCore.checkForDuplicates(tokenIds);

        uint256 totalETHCost;
        address[] memory paymentTokens = new address[](length);
        uint256[] memory tokenCosts = new uint256[](length);
        uint256 uniqueTokenCount;
        
        for (uint256 i; i < length; ) {
            if (quantities[i] == 0) revert VendingMachineCore.ZeroAmount();
            
            VendingMachineCore.validatePurchaseVersioned(
                tokenIds[i],
                quantities[i],
                _activeSales,
                saleConfigs,
                versionedUserPurchases,
                ksItems,
                msg.sender
            );
            
            VendingMachineCore.SaleConfig memory config = saleConfigs[tokenIds[i]];
            uint256 cost = uint256(config.price) * quantities[i];
            
            if (config.paymentToken == address(0)) {
                totalETHCost += cost;
            } else {
                bool found = false;
                for (uint256 j; j < uniqueTokenCount; ) {
                    if (paymentTokens[j] == config.paymentToken) {
                        tokenCosts[j] += cost;
                        found = true;
                        break;
                    }
                    unchecked {
                        ++j;
                    }
                }
                if (!found) {
                    paymentTokens[uniqueTokenCount] = config.paymentToken;
                    tokenCosts[uniqueTokenCount] = cost;
                    unchecked {
                        ++uniqueTokenCount;
                    }
                }
            }
            unchecked {
                ++i;
            }
        }
        if (totalETHCost > 0 && msg.value < totalETHCost) {
            revert VendingMachineCore.InsufficientPayment();
        }
        for (uint256 i; i < uniqueTokenCount; ) {
            SafeTransferLib.safeTransferFrom(
                paymentTokens[i],
                msg.sender,
                fundsRecipient,
                tokenCosts[i]
            );
            unchecked {
                ++i;
            }
        }
        uint256[] memory batchTokenIds = new uint256[](length);
        uint256[] memory batchQuantities = new uint256[](length);

        for (uint256 i; i < length; ) {
            VendingMachineOps.updatePurchaseStateVersioned(
                tokenIds[i],
                quantities[i],
                saleConfigs,
                versionedUserPurchases,
                msg.sender
            );
            
            batchTokenIds[i] = tokenIds[i];
            batchQuantities[i] = quantities[i];
            
            emit Purchase(
                msg.sender,
                tokenIds[i],
                quantities[i],
                saleConfigs[tokenIds[i]].price,
                saleConfigs[tokenIds[i]].paymentToken
            );

            unchecked {
                ++i;
            }
        }
        
        ksItems.safeBatchTransferFrom(
            address(this),
            msg.sender,
            batchTokenIds,
            batchQuantities,
            ""
        );
        
        if (totalETHCost > 0) {
            fundsRecipient.safeTransferETH(totalETHCost);
            if (msg.value > totalETHCost) {
                msg.sender.safeTransferETH(msg.value - totalETHCost);
            }
        }
    }

    /// @notice Configures or updates a sale for a specific token ID.
    /// @dev Can only be called by the owner. Creates a NEW sale with version increment.
    /// @param tokenId The token ID to configure.
    /// @param price The price per token.
    /// @param startTime The sale start timestamp.
    /// @param endTime The sale end timestamp.
    /// @param maxSupply The maximum supply available for sale.
    /// @param maxPerAddress The maximum per address (0 for unlimited).
    /// @param paymentToken The payment token address (address(0) for ETH).
    /// @param checkInventory If true, verifies contract holds at least maxSupply tokens.
    function configSale(
        uint256 tokenId,
        uint128 price,
        uint64 startTime,
        uint64 endTime,
        uint32 maxSupply,
        uint32 maxPerAddress,
        address paymentToken,
        bool checkInventory
    ) external onlyOwner {
        if (price == 0) revert VendingMachineCore.ZeroAmount();
        if (startTime >= endTime) revert VendingMachineCore.InvalidTimeRange();
        if (maxSupply == 0) revert VendingMachineCore.ZeroAmount();
        if (saleConfigs[tokenId].active) {
            revert VendingMachineCore.SaleMustBeInactive();
        }
        if (checkInventory) {
            uint256 contractBalance = ksItems.balanceOf(address(this), tokenId);
            if (contractBalance < maxSupply) revert VendingMachineCore.InsufficientInventory();
        }

        uint64 newVersion = saleConfigs[tokenId].saleVersion + 1;
        saleConfigs[tokenId] = VendingMachineCore.SaleConfig({
            price: price,
            startTime: startTime,
            endTime: endTime,
            maxSupply: maxSupply,
            maxPerAddress: maxPerAddress,
            totalSold: 0,
            paymentToken: paymentToken,
            active: true,
            saleVersion: newVersion
        });
        
        _activeSales.set(tokenId);
        VendingMachineOps.addToActiveArray(
            tokenId,
            activeSaleTokenIds,
            _isInActiveArray,
            _tokenIdToArrayIndex
        );

        emit SaleConfigured(tokenId, price, startTime, endTime, maxSupply, maxPerAddress, paymentToken);
    }

    /// @notice Updates specific parameters of an existing sale without resetting purchase tracking.
    /// @dev Can only be called by the owner. Does NOT reset totalSold or user purchases.
    /// @param tokenId The token ID to update.
    /// @param newPrice The new price per token (use current price if no change desired).
    /// @param newEndTime The new end timestamp (must be >= current endTime).
    function updateSaleParams(
        uint256 tokenId,
        uint128 newPrice,
        uint64 newEndTime
    ) external onlyOwner {
        VendingMachineCore.SaleConfig storage config = saleConfigs[tokenId];
        if (config.price == 0) revert VendingMachineCore.SaleNotFound();
        if (newPrice == 0) revert VendingMachineCore.ZeroAmount();
        if (newEndTime < config.endTime) revert VendingMachineCore.InvalidParam();

        config.price = newPrice;
        config.endTime = newEndTime;

        emit SaleParamsUpdated(tokenId, newPrice, newEndTime);
    }

    /// @notice Activates or deactivates a sale for a token ID.
    /// @dev Can only be called by the owner. Emits SaleStatusUpdated event.
    /// @param tokenId The token ID to update.
    /// @param active True to activate, false to deactivate.
    function setSaleStatus(uint256 tokenId, bool active) external onlyOwner {
        if (saleConfigs[tokenId].price == 0) revert VendingMachineCore.SaleNotFound();
        VendingMachineCore.SaleConfig storage config = saleConfigs[tokenId];
        if (active) {
            if (config.startTime >= config.endTime) revert VendingMachineCore.InvalidTimeRange();
            if (config.maxSupply == 0 || config.totalSold > config.maxSupply)
                revert VendingMachineCore.ExceedsMaxSupply();

            uint256 contractBalance = ksItems.balanceOf(address(this), tokenId);
            if (contractBalance < (config.maxSupply - config.totalSold)) {
                revert VendingMachineCore.InsufficientInventory();
            }

            _activeSales.set(tokenId);
            VendingMachineOps.addToActiveArray(
                tokenId,
                activeSaleTokenIds,
                _isInActiveArray,
                _tokenIdToArrayIndex
            );
        } else {
            _activeSales.unset(tokenId);
            VendingMachineOps.removeFromActiveArray(
                tokenId,
                activeSaleTokenIds,
                _isInActiveArray,
                _tokenIdToArrayIndex
            );
        }

        config.active = active;
        emit SaleStatusUpdated(tokenId, active);
    }

    /// @notice Sets the address of the ERC1155 contract for items.
    /// @dev Can only be called by the owner. Emits KSItemsUpdated event.
    /// @param _ksItems The new address of the ERC1155 contract.
    function setKSItems(address _ksItems) external onlyOwner {
        if (_ksItems == address(0)) revert VendingMachineCore.ZeroAddress();
        address old = address(ksItems);
        ksItems = IERC1155(_ksItems);
        emit KSItemsUpdated(old, _ksItems);
    }

    /// @notice Sets the recipient address for funds from sales.
    /// @dev Can only be called by the owner. Emits FundsRecipientChanged event.
    /// @param _fundsRecipient The new address to receive funds.
    function setFundsRecipient(address _fundsRecipient) external onlyOwner {
        if (_fundsRecipient == address(0)) revert VendingMachineCore.ZeroAddress();
        address old = fundsRecipient;
        fundsRecipient = _fundsRecipient;
        emit FundsRecipientChanged(old, _fundsRecipient);
    }

    /// @notice Pause state for all purchases.
    /// @dev Can only be called by the owner. Emits SalesPaused event.
    /// @param _paused True to pause, false to unpause.
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit SalesPaused(_paused);
    }

    /// @notice Batch withdrawal of tokens to the owner.
    /// @dev Can only be called by the owner. Prevents withdrawing inventory needed for active sales.
    /// @param tokenIds Array of token IDs to withdraw.
    /// @param amounts Array of amounts corresponding to each token ID.
    function emsWithdrawBatch(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external onlyOwner {
        if (tokenIds.length != amounts.length) revert VendingMachineCore.ArrayLengthMismatch();
        if (tokenIds.length == 0) revert VendingMachineCore.ZeroAmount();
        for (uint256 i; i < tokenIds.length; ) {
            uint256 tokenId = tokenIds[i];
            if (_activeSales.get(tokenId)) {
                VendingMachineCore.SaleConfig memory config = saleConfigs[tokenId];
                uint256 needed = config.maxSupply - config.totalSold;
                uint256 currentBalance = ksItems.balanceOf(address(this), tokenId);

                if (currentBalance < amounts[i] + needed) {
                    revert VendingMachineCore.ActiveSaleInventoryRequired();
                }
            }

            unchecked {
                ++i;
            }
        }

        ksItems.safeBatchTransferFrom(address(this), msg.sender, tokenIds, amounts, "");
        emit BatchTokensWithdrawn(msg.sender, tokenIds, amounts);
    }

    /// @notice Maintenance withdrawal of all ETH balance to the owner.
    /// @dev Can only be called by the owner. Emits ETHWithdrawn event.
    function wdETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert VendingMachineCore.ZeroAmount();
        msg.sender.safeTransferETH(balance);
        emit ETHWithdrawn(msg.sender, balance);
    }

    /// @notice Maintenance withdrawal of all balance of a specific ERC20 token to the owner.
    /// @dev Can only be called by the owner. Emits ERC20Withdrawn event.
    /// @param token The ERC20 token address.
    function wdERC20(address token) external onlyOwner {
        if (token == address(0)) revert VendingMachineCore.ZeroAddress();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert VendingMachineCore.ZeroAmount();
        SafeTransferLib.safeTransfer(token, msg.sender, balance);
        emit ERC20Withdrawn(msg.sender, token, balance);
    }

    /// @notice Returns all token IDs for currently active sales.
    /// @return Array of active token IDs.
    function getActiveSaleTokenIds() external view returns (uint256[] memory) {
        return activeSaleTokenIds;
    }

    /// @notice Returns the count of active sales.
    /// @return The number of active sales.
    function getActiveSales() external view returns (uint256) {
        return activeSaleTokenIds.length;
    }

    /// @notice Returns a paginated batch of active sales.
    /// @dev Useful for off-chain querying to avoid gas limits on large arrays.
    /// @param startIndex The starting index in the active array.
    /// @param count The number of items to return.
    /// @return tokenIds Array of token IDs in the batch.
    /// @return configs Array of SaleConfig structs for the batch.
    function getActiveSalesBatch(
        uint256 startIndex,
        uint256 count
    )
        external
        view
        returns (uint256[] memory tokenIds, VendingMachineCore.SaleConfig[] memory configs)
    {
        uint256 length = activeSaleTokenIds.length;
        if (startIndex >= length) {
            return (new uint256[](0), new VendingMachineCore.SaleConfig[](0));
        }
        uint256 endIndex = startIndex + count;
        if (endIndex > length) {
            endIndex = length;
        }
        uint256 actualCount = endIndex - startIndex;
        tokenIds = new uint256[](actualCount);
        configs = new VendingMachineCore.SaleConfig[](actualCount);
        for (uint256 i; i < actualCount; ) {
            uint256 tokenId = activeSaleTokenIds[startIndex + i];
            tokenIds[i] = tokenId;
            configs[i] = saleConfigs[tokenId];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns all currently live sales (active and within time range).
    /// @dev Filters active sales that are live based on current timestamp.
    /// @return tokenIds Array of live token IDs.
    /// @return configs Array of SaleConfig structs for live sales.
    function getLiveSales()
        external
        view
        returns (uint256[] memory tokenIds, VendingMachineCore.SaleConfig[] memory configs)
    {
        uint256 currentTime = block.timestamp;
        uint256 activeCount = activeSaleTokenIds.length;
        uint256 liveCount = 0;
        for (uint256 i; i < activeCount; ) {
            uint256 tokenId = activeSaleTokenIds[i];
            VendingMachineCore.SaleConfig memory config = saleConfigs[tokenId];
            if (VendingMachineCore.isLive(config, currentTime)) {
                unchecked {
                    ++liveCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        tokenIds = new uint256[](liveCount);
        configs = new VendingMachineCore.SaleConfig[](liveCount);
        uint256 index = 0;

        for (uint256 i; i < activeCount; ) {
            uint256 tokenId = activeSaleTokenIds[i];
            VendingMachineCore.SaleConfig memory config = saleConfigs[tokenId];
            if (VendingMachineCore.isLive(config, currentTime)) {
                tokenIds[index] = tokenId;
                configs[index] = config;
                unchecked {
                    ++index;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Retrieves sale information for a specific token ID.
    /// @dev Returns unpacked values for gas efficiency.
    /// @param tokenId The token ID to query.
    /// @return price The price per token.
    /// @return startTime The sale start timestamp.
    /// @return endTime The sale end timestamp.
    /// @return maxSupply The maximum supply.
    /// @return maxPerAddress The max per address.
    /// @return totalSold The total sold so far.
    /// @return paymentToken The payment token address.
    /// @return active Whether the sale is active.
    /// @return isLive Whether the sale is currently live.
    function getSaleInfo(
        uint256 tokenId
    )
        external
        view
        returns (
            uint128 price,
            uint64 startTime,
            uint64 endTime,
            uint32 maxSupply,
            uint32 maxPerAddress,
            uint32 totalSold,
            address paymentToken,
            bool active,
            bool isLive
        )
    {
        VendingMachineCore.SaleConfig memory config = saleConfigs[tokenId];
        uint256 currentTime = block.timestamp;
        return (
            config.price,
            config.startTime,
            config.endTime,
            config.maxSupply,
            config.maxPerAddress,
            config.totalSold,
            config.paymentToken,
            config.active,
            VendingMachineCore.isLive(config, currentTime)
        );
    }

    /// @notice Retrieves purchase information for a user and token ID.
    /// @dev Computes remaining allocation and purchase eligibility using versioned tracking.
    /// @param tokenId The token ID to query.
    /// @param user The user's address.
    /// @return purchased The amount purchased by the user in the current sale version.
    /// @return remainingAllocation The remaining amount the user can purchase.
    /// @return canPurchase Whether the user can make a purchase now.
    function getUserPurchaseInfo(
        uint256 tokenId,
        address user
    )
        external
        view
        returns (uint32 purchased, uint32 remainingAllocation, bool canPurchase)
    {
        VendingMachineCore.SaleConfig memory config = saleConfigs[tokenId];
        bytes32 key = VendingMachineCore.getVersionedPurchaseKey(
            tokenId,
            config.saleVersion,
            user
        );
        purchased = versionedUserPurchases[key];
        
        if (config.maxPerAddress == 0) {
            remainingAllocation = config.maxSupply > config.totalSold
                ? config.maxSupply - config.totalSold
                : 0;
        } else {
            remainingAllocation = config.maxPerAddress > purchased
                ? config.maxPerAddress - purchased
                : 0;
        }
        
        canPurchase =
            config.active &&
            block.timestamp >= config.startTime &&
            block.timestamp <= config.endTime &&
            remainingAllocation > 0 &&
            config.totalSold < config.maxSupply;
    }

    /// @notice Checks if a sale is active for a token ID.
    /// @param tokenId The token ID to check.
    /// @return True if the sale is active.
    function isSaleActive(uint256 tokenId) external view returns (bool) {
        return _activeSales.get(tokenId);
    }

    /// @notice Returns the remaining supply for a token ID.
    /// @param tokenId The token ID to query.
    /// @return The remaining supply available for sale.
    function getRemainingSupply(uint256 tokenId) external view returns (uint32) {
        VendingMachineCore.SaleConfig memory config = saleConfigs[tokenId];
        return
            config.maxSupply > config.totalSold
                ? config.maxSupply - config.totalSold
                : 0;
    }

    /// @dev Fallback function to receive ETH payments.
    receive() external payable {}
    fallback() external payable receiverFallback {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x3c10b94e)
            revert(0x1c, 0x04)
        }
    }

    modifier receiverFallback() {
        _beforeReceiverFallbackBody();
        if (_useReceiverFallbackBody()) {
            /// @solidity memory-safe-assembly
            assembly {
                let s := shr(224, calldataload(0))
                if or(
                    eq(s, 0x150b7a02),
                    or(eq(s, 0xf23a6e61), eq(s, 0xbc197c81))
                ) {
                    mstore(0x20, s)
                    return(0x3c, 0x20)
                }
            }
        }
        _afterReceiverFallbackBody();
        _;
    }

    function _useReceiverFallbackBody() internal view virtual returns (bool) {
        return true;
    }

    function _beforeReceiverFallbackBody() internal virtual {}
    function _afterReceiverFallbackBody() internal virtual {}

    /// @notice Handles receipt of a single ERC1155 token.
    /// @dev Required for IERC1155Receiver interface. Only accepts tokens from ksItems contract.
    /// @return The selector confirming support.
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        if (address(ksItems) == address(0)) revert VendingMachineCore.NotInitialized();
        if (msg.sender != address(ksItems)) {
            revert VendingMachineCore.UnauthorizedTokenTransfer();
        }
        return this.onERC1155Received.selector;
    }

    /// @notice Handles receipt of multiple ERC1155 tokens.
    /// @dev Required for IERC1155Receiver interface; returns the magic selector to confirm support.
    /// @return The selector confirming support.
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external view returns (bytes4) {
        if (address(ksItems) == address(0)) revert VendingMachineCore.NotInitialized();
        if (msg.sender != address(ksItems)) {
            revert VendingMachineCore.UnauthorizedTokenTransfer();
        }
        return this.onERC1155BatchReceived.selector;
    }

    /// @notice Checks if the contract supports a given interface.
    /// @dev Required for IERC1155Receiver and general interface detection.
    /// @param interfaceId The interface ID to check.
    /// @return True if supported, false otherwise.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x4e2312e0 || // IERC1155Receiver
            interfaceId == 0x01ffc9a7; // ERC165
    }
}
