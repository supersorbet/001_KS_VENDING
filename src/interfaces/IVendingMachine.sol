// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {VendingMachineCore} from "../libraries/VendingMachineCore.sol";

/// @title IVendingMachine
/// @notice Interface for the KS Vending Machine contract
interface IVendingMachine {
    
    function purchase(uint256 tokenId, uint32 quantity) external payable;

    function purchaseBatch(
        uint256[] calldata tokenIds,
        uint32[] calldata quantities
    ) external payable;

    function purchaseBatchOptimized(
        uint256[] calldata tokenIds,
        uint32[] calldata quantities
    ) external payable;

    function configSale(
        uint256 tokenId,
        uint128 price,
        uint64 startTime,
        uint64 endTime,
        uint32 maxSupply,
        uint32 maxPerAddress,
        address paymentToken,
        bool checkInventory
    ) external;

    function updateSaleParams(
        uint256 tokenId,
        uint128 newPrice,
        uint64 newEndTime
    ) external;

    function setSaleStatus(uint256 tokenId, bool active) external;
    function setKSItems(address _ksItems) external;
    function setFundsRecipient(address _fundsRecipient) external;
    function setPaused(bool _paused) external;

    function emsWithdrawBatch(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external;

    function wdETH() external;
    function wdERC20(address token) external;

    function getActiveSaleTokenIds() external view returns (uint256[] memory);
    function getActiveSales() external view returns (uint256);

    function getActiveSalesBatch(
        uint256 startIndex,
        uint256 count
    )
        external
        view
        returns (
            uint256[] memory tokenIds,
            VendingMachineCore.SaleConfig[] memory configs
        );

    function getLiveSales()
        external
        view
        returns (
            uint256[] memory tokenIds,
            VendingMachineCore.SaleConfig[] memory configs
        );

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
        );

    function getUserPurchaseInfo(
        uint256 tokenId,
        address user
    )
        external
        view
        returns (
            uint32 purchased,
            uint32 remainingAllocation,
            bool canPurchase
        );

    function isSaleActive(uint256 tokenId) external view returns (bool);
    function getRemainingSupply(uint256 tokenId) external view returns (uint32);

    event SaleConfigured(
        uint256 indexed tokenId,
        uint128 price,
        uint64 startTime,
        uint64 endTime,
        uint32 maxSupply,
        uint32 maxPerAddress,
        address paymentToken
    );

    event Purchase(
        address indexed buyer,
        uint256 indexed tokenId,
        uint32 quantity,
        uint128 price,
        address paymentToken
    );

    event SaleStatusUpdated(uint256 indexed tokenId, bool active);
    event SaleParamsUpdated(
        uint256 indexed tokenId,
        uint128 newPrice,
        uint64 newEndTime
    );
    event KSItemsUpdated(
        address indexed oldKSItems,
        address indexed newKSItems
    );
    event FundsRecipientChanged(
        address indexed oldRecipient,
        address indexed newRecipient
    );
    event SalesPaused(bool paused);
    event BatchTokensWithdrawn(
        address indexed to,
        uint256[] tokenIds,
        uint256[] amounts
    );
    event ETHWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(
        address indexed to,
        address indexed token,
        uint256 amount
    );

}
