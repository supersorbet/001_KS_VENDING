// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {KSVendingMachineOP_Patched} from "../../src/contracts/KSVendingMachineOP_PATCHED.sol";
import {VendingMachineCore} from "../../src/libraries/VendingMachineCore.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title VendingMachine Integration Tests
/// @notice integration tests for the vending machine contract
contract VendingMachineTest is Test {
    KSVendingMachineOP_Patched public vendingMachine;
    MockERC1155 public ksItems;
    MockERC20 public paymentToken;
    address public owner;
    address public fundsRecipient;
    address public buyer;
    address public buyer2;

    uint256 public constant TOKEN_ID = 1;
    uint256 public constant INITIAL_SUPPLY = 1000;
    uint128 public constant PRICE = 1 ether;
    uint32 public constant MAX_SUPPLY = 100;
    uint32 public constant MAX_PER_ADDRESS = 10;

    event Purchase(
        address indexed buyer,
        uint256 indexed tokenId,
        uint32 quantity,
        uint128 price,
        address paymentToken
    );
    event SaleConfigured(
        uint256 indexed tokenId,
        uint128 price,
        uint64 startTime,
        uint64 endTime,
        uint32 maxSupply,
        uint32 maxPerAddress,
        address paymentToken
    );

    function setUp() public {
        owner = address(this);
        fundsRecipient = address(0x100);
        buyer = address(0x200);
        buyer2 = address(0x300);

        // Deploy contracts
        vendingMachine = new KSVendingMachineOP_Patched();
        ksItems = new MockERC1155();
        paymentToken = new MockERC20();

        // Setup
        vm.deal(buyer, 200 ether);
        vm.deal(buyer2, 200 ether);
        paymentToken.mint(buyer, 100 ether);
        paymentToken.mint(buyer2, 100 ether);

        // Initialize vending machine
        vendingMachine.setKSItems(address(ksItems));
        vendingMachine.setFundsRecipient(fundsRecipient);

        // Mint tokens to vending machine
        ksItems.mint(address(vendingMachine), TOKEN_ID, INITIAL_SUPPLY);
    }

    // ============================================================================
    // CONFIGURATION TESTS
    // ============================================================================

    function test_configSale_ETH() public {
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = uint64(block.timestamp + 1 days);

        vm.expectEmit(true, false, false, true);
        emit SaleConfigured(
            TOKEN_ID,
            PRICE,
            startTime,
            endTime,
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(0)
        );

        vendingMachine.configSale(
            TOKEN_ID,
            PRICE,
            startTime,
            endTime,
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(0),
            false
        );

        (
            uint128 configPrice,
            uint64 configStartTime,
            uint64 configEndTime,
            uint32 configMaxSupply,
            uint32 configMaxPerAddress,
            uint32 configTotalSold,
            address configPaymentToken,
            bool configActive,
            uint64 configSaleVersion
        ) = vendingMachine.saleConfigs(TOKEN_ID);
        
        assertEq(configPrice, PRICE);
        assertEq(configMaxSupply, MAX_SUPPLY);
        assertEq(configMaxPerAddress, MAX_PER_ADDRESS);
        assertTrue(configActive);
        assertEq(configPaymentToken, address(0));
    }

    function test_configSale_ERC20() public {
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = uint64(block.timestamp + 1 days);

        vendingMachine.configSale(
            TOKEN_ID,
            PRICE,
            startTime,
            endTime,
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(paymentToken),
            false
        );

        (
            uint128 configPrice,
            uint64 configStartTime,
            uint64 configEndTime,
            uint32 configMaxSupply,
            uint32 configMaxPerAddress,
            uint32 configTotalSold,
            address configPaymentToken,
            bool configActive,
            uint64 configSaleVersion
        ) = vendingMachine.saleConfigs(TOKEN_ID);
        
        assertEq(configPaymentToken, address(paymentToken));
    }

    function test_configSale_RequiresInactive() public {
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = uint64(block.timestamp + 1 days);

        vendingMachine.configSale(
            TOKEN_ID,
            PRICE,
            startTime,
            endTime,
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(0),
            false
        );

        // Try to reconfigure active sale
        vm.expectRevert(VendingMachineCore.SaleMustBeInactive.selector);
        vendingMachine.configSale(
            TOKEN_ID,
            PRICE + 1,
            startTime,
            endTime,
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(0),
            false
        );
    }

    function test_configSale_ZeroPrice() public {
        vm.expectRevert(VendingMachineCore.ZeroAmount.selector);
        vendingMachine.configSale(
            TOKEN_ID,
            0,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(0),
            false
        );
    }

    function test_configSale_InvalidTimeRange() public {
        vm.expectRevert(VendingMachineCore.InvalidTimeRange.selector);
        vendingMachine.configSale(
            TOKEN_ID,
            PRICE,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp),
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(0),
            false
        );
    }

    // ============================================================================
    // PURCHASE TESTS
    // ============================================================================

    function test_purchase_ETH_Success() public {
        _configureSale();

        uint32 quantity = 5;
        uint256 totalCost = uint256(PRICE) * quantity;

        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit Purchase(buyer, TOKEN_ID, quantity, PRICE, address(0));
        vendingMachine.purchase{value: totalCost}(TOKEN_ID, quantity);

        assertEq(ksItems.balanceOf(buyer, TOKEN_ID), quantity);
        assertEq(fundsRecipient.balance, totalCost);
    }

    function test_purchase_ERC20_Success() public {
        _configureSaleERC20();

        uint32 quantity = 5;
        uint256 totalCost = uint256(PRICE) * quantity;

        vm.startPrank(buyer);
        paymentToken.approve(address(vendingMachine), totalCost);
        vm.expectEmit(true, true, false, true);
        emit Purchase(buyer, TOKEN_ID, quantity, PRICE, address(paymentToken));
        vendingMachine.purchase(TOKEN_ID, quantity);
        vm.stopPrank();

        assertEq(ksItems.balanceOf(buyer, TOKEN_ID), quantity);
        assertEq(paymentToken.balanceOf(fundsRecipient), totalCost);
    }

    function test_purchase_InsufficientPayment() public {
        _configureSale();

        uint32 quantity = 5;
        uint256 insufficientAmount = uint256(PRICE) * quantity - 1;

        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.InsufficientPayment.selector);
        vendingMachine.purchase{value: insufficientAmount}(TOKEN_ID, quantity);
    }

    function test_purchase_ExceedsMaxSupply() public {
        _configureSale();

        uint32 quantity = MAX_SUPPLY + 1;
        uint256 totalCost = uint256(PRICE) * quantity;

        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.ExceedsMaxSupply.selector);
        vendingMachine.purchase{value: totalCost}(
            TOKEN_ID,
            quantity
        );
    }

    function test_purchase_ExceedsMaxPerAddress() public {
        _configureSale();

        uint32 quantity = MAX_PER_ADDRESS + 1;

        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.ExceedsMaxPerAddress.selector);
        vendingMachine.purchase{value: uint256(PRICE) * quantity}(
            TOKEN_ID,
            quantity
        );
    }

    function test_purchase_MultiplePurchases() public {
        _configureSale();

        uint32 quantity1 = 5;
        uint32 quantity2 = 3;

        vm.prank(buyer);
        vendingMachine.purchase{value: uint256(PRICE) * quantity1}(
            TOKEN_ID,
            quantity1
        );

        vm.prank(buyer);
        vendingMachine.purchase{value: uint256(PRICE) * quantity2}(
            TOKEN_ID,
            quantity2
        );

        assertEq(ksItems.balanceOf(buyer, TOKEN_ID), quantity1 + quantity2);
    }

    function test_purchase_ExceedsMaxPerAddressAfterMultiple() public {
        _configureSale();

        uint32 quantity1 = MAX_PER_ADDRESS;
        uint32 quantity2 = 1;

        vm.prank(buyer);
        vendingMachine.purchase{value: uint256(PRICE) * quantity1}(
            TOKEN_ID,
            quantity1
        );

        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.ExceedsMaxPerAddress.selector);
        vendingMachine.purchase{value: uint256(PRICE) * quantity2}(
            TOKEN_ID,
            quantity2
        );
    }

    function test_purchase_SaleNotActive() public {
        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.SaleNotActive.selector);
        vendingMachine.purchase{value: PRICE}(TOKEN_ID, 1);
    }

    function test_purchase_ZeroQuantity() public {
        _configureSale();

        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.ZeroAmount.selector);
        vendingMachine.purchase{value: PRICE}(TOKEN_ID, 0);
    }

    // ============================================================================
    // BATCH PURCHASE TESTS
    // ============================================================================

    function test_purchaseBatch_Success() public {
        _configureSale();
        
        // Configure a second sale for a different token
        uint256 TOKEN_ID_2 = TOKEN_ID + 1;
        ksItems.mint(address(vendingMachine), TOKEN_ID_2, INITIAL_SUPPLY);
        vendingMachine.configSale(
            TOKEN_ID_2,
            PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(0),
            false
        );

        uint256[] memory tokenIds = new uint256[](2);
        uint32[] memory quantities = new uint32[](2);
        tokenIds[0] = TOKEN_ID;
        tokenIds[1] = TOKEN_ID_2; // Different token ID
        quantities[0] = 3;
        quantities[1] = 2;

        uint256 totalCost = uint256(PRICE) * (quantities[0] + quantities[1]);

        vm.prank(buyer);
        vendingMachine.purchaseBatch{value: totalCost}(tokenIds, quantities);

        assertEq(ksItems.balanceOf(buyer, TOKEN_ID), 3);
        assertEq(ksItems.balanceOf(buyer, TOKEN_ID_2), 2);
    }

    function test_purchaseBatch_DuplicateTokenIds() public {
        _configureSale();

        uint256[] memory tokenIds = new uint256[](2);
        uint32[] memory quantities = new uint32[](2);
        tokenIds[0] = TOKEN_ID;
        tokenIds[1] = TOKEN_ID; // Duplicate
        quantities[0] = 3;
        quantities[1] = 2;

        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.DuplicateTokenId.selector);
        vendingMachine.purchaseBatch{value: 10 ether}(tokenIds, quantities);
    }

    function test_purchaseBatch_ExceedsMaxBatchSize() public {
        _configureSale();

        uint256[] memory tokenIds = new uint256[](51);
        uint32[] memory quantities = new uint32[](51);

        for (uint256 i; i < 51; i++) {
            tokenIds[i] = TOKEN_ID;
            quantities[i] = 1;
        }

        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.BatchTooLarge.selector);
        vendingMachine.purchaseBatch{value: 100 ether}(tokenIds, quantities);
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    function _configureSale() internal {
        vendingMachine.configSale(
            TOKEN_ID,
            PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(0),
            false
        );
    }

    function _configureSaleERC20() internal {
        vendingMachine.configSale(
            TOKEN_ID,
            PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 1 days),
            MAX_SUPPLY,
            MAX_PER_ADDRESS,
            address(paymentToken),
            false
        );
    }
}

