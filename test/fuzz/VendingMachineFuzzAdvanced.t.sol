// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {KSVendingMachineOP_Patched} from "../../src/contracts/KSVendingMachineOP_PATCHED.sol";
import {VendingMachineCore} from "../../src/libraries/VendingMachineCore.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title Advanced Vending Machine Fuzz Tests
/// @notice Comprehensive fuzz testing covering edge cases, invariants, and error conditions
contract VendingMachineFuzzAdvancedTest is Test {
    KSVendingMachineOP_Patched public vendingMachine;
    MockERC1155 public ksItems;
    MockERC20 public paymentToken;
    
    address public owner;
    address public fundsRecipient;
    address public buyer;
    address public buyer2;
    
    uint32 public constant INITIAL_SUPPLY = 10000;
    uint128 public constant BASE_PRICE = 1 ether;
    
    // Track state for invariants
    mapping(uint256 => uint256) public totalPurchased;
    mapping(uint256 => mapping(address => uint256)) public userPurchases;
    mapping(uint256 => uint256) public totalRevenue;

    function setUp() public {
        owner = address(this);
        fundsRecipient = address(0x100);
        buyer = address(0x200);
        buyer2 = address(0x300);
        
        // Always deploy fresh contracts
        ksItems = new MockERC1155();
        paymentToken = new MockERC20();
        vendingMachine = new KSVendingMachineOP_Patched();
        
        vendingMachine.setKSItems(address(ksItems));
        vendingMachine.setFundsRecipient(fundsRecipient);
        
        // Mint tokens for multiple token IDs
        for (uint256 i = 1; i <= 10; i++) {
            ksItems.mint(address(vendingMachine), i, uint256(INITIAL_SUPPLY));
        }
        
        // Setup payment tokens and ETH (use safe amounts to avoid overflow)
        paymentToken.mint(buyer, 1000000 ether);
        paymentToken.mint(buyer2, 1000000 ether);
        vm.deal(buyer, 10000 ether);
        vm.deal(buyer2, 10000 ether);
    }

    /// @notice Fuzz test: Purchase with various price ranges
    /// @param price Random price (very wide range)
    /// @param quantity Random quantity
    function testFuzz_Purchase_VariousPrices(
        uint128 price,
        uint32 quantity
    ) public {
        price = uint128(bound(uint256(price), 1 wei, 1000 ether));
        quantity = uint32(bound(uint256(quantity), 1, 100));
        
        uint256 tokenId = 1;
        uint256 totalCost = uint256(price) * quantity;
        
        // Ensure buyer has enough funds
        if (buyer.balance < totalCost) {
            vm.deal(buyer, totalCost);
        }
        
        vendingMachine.configSale(
            tokenId,
            price,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            1000,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Various Prices Test ===");
        console.log("Price:", price);
        console.log("Quantity:", quantity);
        console.log("Total cost:", totalCost);
        
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 recipientBalanceBefore = fundsRecipient.balance;
        
        vm.prank(buyer);
        vendingMachine.purchase{value: totalCost}(tokenId, quantity);
        
        assertEq(buyer.balance, buyerBalanceBefore - totalCost);
        assertEq(fundsRecipient.balance, recipientBalanceBefore + totalCost);
        assertEq(ksItems.balanceOf(buyer, tokenId), quantity);
        
        console.log("[SUCCESS] Purchase with price", price, "successful");
    }

    /// @notice Fuzz test: Max per address limits
    /// @param maxPerAddress Random max per address limit
    /// @param purchaseQuantity Random purchase quantity
    function testFuzz_MaxPerAddressLimit(
        uint32 maxPerAddress,
        uint32 purchaseQuantity
    ) public {
        maxPerAddress = uint32(bound(uint256(maxPerAddress), 1, 1000));
        purchaseQuantity = uint32(bound(uint256(purchaseQuantity), 1, maxPerAddress));
        
        uint256 tokenId = 1;
        
        vendingMachine.configSale(
            tokenId,
            BASE_PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            maxPerAddress,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Max Per Address Test ===");
        console.log("Max per address:", maxPerAddress);
        console.log("Purchase quantity:", purchaseQuantity);
        
        uint256 cost = uint256(BASE_PRICE) * purchaseQuantity;
        vm.deal(buyer, cost);
        
        vm.prank(buyer);
        vendingMachine.purchase{value: cost}(tokenId, purchaseQuantity);
        
        (uint32 purchased, uint32 remaining, bool canPurchase) = 
            vendingMachine.getUserPurchaseInfo(tokenId, buyer);
        
        console.log("User purchased:", purchased);
        console.log("User remaining:", remaining);
        console.log("Can purchase:", canPurchase);
        
        assertEq(purchased, purchaseQuantity);
        assertEq(remaining, maxPerAddress - purchaseQuantity);
        assertTrue(canPurchase || remaining == 0);
    }

    /// @notice Fuzz test: Exceeding max per address should revert
    /// @param maxPerAddress Random max limit
    function testFuzz_ExceedsMaxPerAddress(uint32 maxPerAddress) public {
        maxPerAddress = uint32(bound(uint256(maxPerAddress), 1, 100));
        
        uint256 tokenId = 1;
        uint32 excessQuantity = maxPerAddress + 1;
        
        vendingMachine.configSale(
            tokenId,
            BASE_PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            maxPerAddress,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Exceeds Max Per Address Test ===");
        console.log("Max per address:", maxPerAddress);
        console.log("Attempting to purchase:", excessQuantity);
        
        uint256 cost = uint256(BASE_PRICE) * excessQuantity;
        vm.deal(buyer, cost);
        
        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.ExceedsMaxPerAddress.selector);
        vendingMachine.purchase{value: cost}(tokenId, excessQuantity);
        
        console.log("[SUCCESS] Correctly reverted on exceeding max per address");
    }

    /// @notice Fuzz test: Exceeding max supply should revert
    /// @param maxSupply Random max supply
    function testFuzz_ExceedsMaxSupply(uint32 maxSupply) public {
        maxSupply = uint32(bound(uint256(maxSupply), 1, INITIAL_SUPPLY));
        
        uint256 tokenId = 1;
        uint32 excessQuantity = maxSupply + 1;
        
        vendingMachine.configSale(
            tokenId,
            BASE_PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            maxSupply,
            1000,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Exceeds Max Supply Test ===");
        console.log("Max supply:", maxSupply);
        console.log("Attempting to purchase:", excessQuantity);
        
        uint256 cost = uint256(BASE_PRICE) * excessQuantity;
        vm.deal(buyer, cost);
        
        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.ExceedsMaxSupply.selector);
        vendingMachine.purchase{value: cost}(tokenId, excessQuantity);
        
        console.log("[SUCCESS] Correctly reverted on exceeding max supply");
    }

    /// @notice Fuzz test: Insufficient payment should revert
    /// @param price Random price
    /// @param quantity Random quantity
    /// @param paymentMultiplier Payment multiplier (less than 1 = insufficient)
    function testFuzz_InsufficientPayment(
        uint128 price,
        uint32 quantity,
        uint256 paymentMultiplier
    ) public {
        price = uint128(bound(uint256(price), 0.001 ether, 100 ether));
        quantity = uint32(bound(uint256(quantity), 1, 100));
        paymentMultiplier = bound(paymentMultiplier, 1, 99); // 1-99% of required payment
        
        uint256 tokenId = 1;
        uint256 requiredCost = uint256(price) * quantity;
        uint256 sentPayment = (requiredCost * paymentMultiplier) / 100;
        
        vendingMachine.configSale(
            tokenId,
            price,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            1000,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Insufficient Payment Test ===");
        console.log("Required cost:", requiredCost);
        console.log("Sent payment:", sentPayment);
        console.log("Payment percentage:", paymentMultiplier);
        
        vm.deal(buyer, sentPayment);
        
        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.InsufficientPayment.selector);
        vendingMachine.purchase{value: sentPayment}(tokenId, quantity);
        
        console.log("[SUCCESS] Correctly reverted on insufficient payment");
    }

    /// @notice Fuzz test: Sale time boundaries
    /// @param startOffset Start time offset from now
    /// @param duration Sale duration
    function testFuzz_SaleTimeBoundaries(
        int256 startOffset,
        uint64 duration
    ) public {
        duration = uint64(bound(uint256(duration), 1 hours, 365 days));
        startOffset = bound(startOffset, -1 days, 0); // Can start in past or now, but not future
        
        uint256 tokenId = 1;
        uint64 startTime;
        if (startOffset < 0) {
            uint256 absOffset = uint256(-startOffset);
            if (absOffset >= block.timestamp) {
                startTime = 1; // Can't go below 1
            } else {
                startTime = uint64(block.timestamp - absOffset);
            }
        } else {
            startTime = uint64(block.timestamp + uint256(startOffset));
        }
        uint64 endTime = startTime + duration;
        
        vendingMachine.configSale(
            tokenId,
            BASE_PRICE,
            startTime,
            endTime,
            INITIAL_SUPPLY,
            1000,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Sale Time Boundaries Test ===");
        console.log("Start time:", startTime);
        console.log("End time:", endTime);
        console.log("Current time:", block.timestamp);
        console.log("Duration:", duration);
        
        // Try to purchase
        uint256 cost = uint256(BASE_PRICE) * 10;
        vm.deal(buyer, cost);
        
        if (block.timestamp >= startTime && block.timestamp <= endTime) {
            vm.prank(buyer);
            vendingMachine.purchase{value: cost}(tokenId, 10);
            console.log("[SUCCESS] Purchase succeeded during valid time window");
        } else {
            vm.prank(buyer);
            vm.expectRevert(VendingMachineCore.SaleNotActive.selector);
            vendingMachine.purchase{value: cost}(tokenId, 10);
            console.log("[SUCCESS] Correctly reverted outside time window");
        }
    }

    /// @notice Fuzz test: Multiple users purchasing same token
    /// @param numUsers Number of users
    /// @param quantityPerUser Quantity per user
    function testFuzz_MultipleUsers(
        uint8 numUsers,
        uint32 quantityPerUser
    ) public {
        numUsers = uint8(bound(uint256(numUsers), 2, 10));
        quantityPerUser = uint32(bound(uint256(quantityPerUser), 1, 50));
        
        uint256 tokenId = 1;
        
        vendingMachine.configSale(
            tokenId,
            BASE_PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            1000,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Multiple Users Test ===");
        console.log("Number of users:", numUsers);
        console.log("Quantity per user:", quantityPerUser);
        
        address[] memory users = new address[](numUsers);
        uint256 cost = uint256(BASE_PRICE) * quantityPerUser;
        
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = address(uint160(0x1000 + i));
            vm.deal(users[i], cost);
            
            vm.prank(users[i]);
            vendingMachine.purchase{value: cost}(tokenId, quantityPerUser);
            
            assertEq(ksItems.balanceOf(users[i], tokenId), quantityPerUser);
            console.log("User", i, "purchased successfully");
        }
        
        // Verify total sold
        (
            uint128 price,
            uint64 startTime,
            uint64 endTime,
            uint32 maxSupply,
            uint32 maxPerAddress,
            uint32 totalSold,
            address paymentToken,
            bool active,
            uint64 saleVersion
        ) = vendingMachine.saleConfigs(tokenId);
        assertEq(totalSold, quantityPerUser * numUsers);
        console.log("Total sold:", totalSold);
        console.log("[SUCCESS] Multiple users purchase successful");
    }

    /// @notice Fuzz test: Update sale parameters
    /// @param newPrice New price
    /// @param newEndTimeOffset New end time offset
    function testFuzz_UpdateSaleParams(
        uint128 newPrice,
        uint64 newEndTimeOffset
    ) public {
        newPrice = uint128(bound(uint256(newPrice), 0.001 ether, 100 ether));
        newEndTimeOffset = uint64(bound(uint256(newEndTimeOffset), 1 days, 365 days));
        
        uint256 tokenId = 1;
        uint64 startTime = uint64(block.timestamp);
        uint64 originalEndTime = uint64(block.timestamp + 30 days);
        
        // Ensure endTime doesn't overflow
        if (originalEndTime < startTime) {
            originalEndTime = type(uint64).max;
        }
        
        vendingMachine.configSale(
            tokenId,
            BASE_PRICE,
            startTime,
            originalEndTime,
            INITIAL_SUPPLY,
            1000,
            address(0),
            false
        );
        
        uint64 newEndTime;
        unchecked {
            uint256 newEndTimeRaw = block.timestamp + newEndTimeOffset;
            newEndTime = newEndTimeRaw > type(uint64).max ? type(uint64).max : uint64(newEndTimeRaw);
        }
        
        // Ensure newEndTime is after startTime
        if (newEndTime <= startTime) {
            newEndTime = startTime + 1;
        }
        
        console.log("\n=== Fuzz Update Sale Params Test ===");
        console.log("Original price:", BASE_PRICE);
        console.log("New price:", newPrice);
        console.log("New end time:", newEndTime);
        
        vendingMachine.updateSaleParams(tokenId, newPrice, newEndTime);
        
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
        ) = vendingMachine.saleConfigs(tokenId);
        
        assertEq(configPrice, newPrice);
        assertEq(configEndTime, newEndTime);
        
        console.log("[SUCCESS] Sale params updated correctly");
    }

    /// @notice Fuzz test: Toggle sale status
    /// @param tokenId Random token ID
    /// @param activeStatus Whether sale should be active
    function testFuzz_ToggleSaleStatus(
        uint256 tokenId,
        bool activeStatus
    ) public {
        tokenId = bound(tokenId, 1, 10);
        
        vendingMachine.configSale(
            tokenId,
            BASE_PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            1000,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Toggle Sale Status Test ===");
        console.log("Token ID:", tokenId);
        console.log("Setting active to:", activeStatus);
        
        vendingMachine.setSaleStatus(tokenId, activeStatus);
        
        (,,,,,,, bool configActive,) = vendingMachine.saleConfigs(tokenId);
        assertEq(configActive, activeStatus);
        
        // Try to purchase
        uint256 cost = uint256(BASE_PRICE) * 10;
        vm.deal(buyer, cost);
        
        vm.prank(buyer);
        if (activeStatus) {
            vendingMachine.purchase{value: cost}(tokenId, 10);
            console.log("[SUCCESS] Purchase succeeded when sale is active");
        } else {
            vm.expectRevert(VendingMachineCore.SaleNotActive.selector);
            vendingMachine.purchase{value: cost}(tokenId, 10);
            console.log("[SUCCESS] Correctly reverted when sale is inactive");
        }
    }

    /// @notice Fuzz test: Batch purchase with various array sizes
    /// @param arraySize Size of the batch array
    function testFuzz_BatchPurchase_VariousSizes(uint8 arraySize) public {
        arraySize = uint8(bound(uint256(arraySize), 2, 10));
        
        console.log("\n=== Fuzz Batch Purchase Various Sizes Test ===");
        console.log("Array size:", arraySize);
        
        // Configure sales for tokens 1-10
        for (uint256 i = 1; i <= 10; i++) {
            vendingMachine.configSale(
                i,
                BASE_PRICE,
                uint64(block.timestamp),
                uint64(block.timestamp + 365 days),
                INITIAL_SUPPLY,
                1000,
                address(0),
                false
            );
        }
        
        uint256[] memory tokenIds = new uint256[](arraySize);
        uint32[] memory quantities = new uint32[](arraySize);
        uint256 totalCost = 0;
        
        // Create unique token IDs
        for (uint256 i = 0; i < arraySize; i++) {
            tokenIds[i] = i + 1;
            quantities[i] = uint32(bound(uint256(i + 1), 1, 10));
            totalCost += uint256(BASE_PRICE) * quantities[i];
        }
        
        console.log("Total cost:", totalCost);
        vm.deal(buyer, totalCost);
        
        vm.prank(buyer);
        vendingMachine.purchaseBatch{value: totalCost}(tokenIds, quantities);
        
        // Verify all purchases
        for (uint256 i = 0; i < arraySize; i++) {
            assertEq(ksItems.balanceOf(buyer, tokenIds[i]), quantities[i]);
            console.log("Token", tokenIds[i], "balance:", quantities[i]);
        }
        
        console.log("[SUCCESS] Batch purchase with", arraySize, "items successful");
    }

    /// @notice Fuzz test: Zero quantity should revert
    /// @param tokenId Random token ID
    function testFuzz_ZeroQuantity(uint256 tokenId) public {
        tokenId = bound(tokenId, 1, 10);
        
        vendingMachine.configSale(
            tokenId,
            BASE_PRICE,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            1000,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Zero Quantity Test ===");
        console.log("Token ID:", tokenId);
        
        vm.deal(buyer, BASE_PRICE);
        
        vm.prank(buyer);
        vm.expectRevert(VendingMachineCore.ZeroAmount.selector);
        vendingMachine.purchase{value: BASE_PRICE}(tokenId, 0);
        
        console.log("[SUCCESS] Correctly reverted on zero quantity");
    }

    /// @notice Fuzz test: ERC20 payment with various amounts
    /// @param price Random price
    /// @param quantity Random quantity
    function testFuzz_ERC20Payment_VariousAmounts(
        uint128 price,
        uint32 quantity
    ) public {
        price = uint128(bound(uint256(price), 0.001 ether, 100 ether));
        quantity = uint32(bound(uint256(quantity), 1, 100));
        
        uint256 tokenId = 1;
        uint256 totalCost = uint256(price) * quantity;
        
        vendingMachine.configSale(
            tokenId,
            price,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            1000,
            address(paymentToken),
            false
        );
        
        console.log("\n=== Fuzz ERC20 Payment Various Amounts Test ===");
        console.log("Price:", price);
        console.log("Quantity:", quantity);
        console.log("Total cost:", totalCost);
        
        vm.prank(buyer);
        paymentToken.approve(address(vendingMachine), totalCost);
        
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);
        uint256 recipientBalanceBefore = paymentToken.balanceOf(fundsRecipient);
        
        vm.prank(buyer);
        vendingMachine.purchase(tokenId, quantity);
        
        assertEq(
            paymentToken.balanceOf(buyer),
            buyerBalanceBefore - totalCost
        );
        assertEq(
            paymentToken.balanceOf(fundsRecipient),
            recipientBalanceBefore + totalCost
        );
        assertEq(ksItems.balanceOf(buyer, tokenId), quantity);
        
        console.log("[SUCCESS] ERC20 payment successful");
    }

    /// @notice Fuzz test: Refund on overpayment
    /// @param price Random price
    /// @param quantity Random quantity
    /// @param overpaymentAmount Random overpayment
    function testFuzz_RefundOnOverpayment(
        uint128 price,
        uint32 quantity,
        uint256 overpaymentAmount
    ) public {
        price = uint128(bound(uint256(price), 0.001 ether, 10 ether));
        quantity = uint32(bound(uint256(quantity), 1, 100));
        overpaymentAmount = bound(overpaymentAmount, 1 ether, 100 ether);
        
        uint256 tokenId = 1;
        uint256 requiredCost = uint256(price) * quantity;
        uint256 totalSent = requiredCost + overpaymentAmount;
        
        vendingMachine.configSale(
            tokenId,
            price,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            1000,
            address(0),
            false
        );
        
        console.log("\n=== Fuzz Refund On Overpayment Test ===");
        console.log("Required cost:", requiredCost);
        console.log("Overpayment:", overpaymentAmount);
        console.log("Total sent:", totalSent);
        
        vm.deal(buyer, totalSent);
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 recipientBalanceBefore = fundsRecipient.balance;
        
        vm.prank(buyer);
        vendingMachine.purchase{value: totalSent}(tokenId, quantity);
        
        uint256 buyerBalanceAfter = buyer.balance;
        uint256 recipientBalanceAfter = fundsRecipient.balance;
        
        console.log("Buyer balance change:", int256(buyerBalanceAfter) - int256(buyerBalanceBefore));
        console.log("Recipient balance change:", int256(recipientBalanceAfter) - int256(recipientBalanceBefore));
        
        assertEq(buyerBalanceBefore - buyerBalanceAfter, requiredCost, "Buyer should only pay required cost");
        assertEq(recipientBalanceAfter - recipientBalanceBefore, requiredCost, "Recipient should receive required cost");
        assertEq(ksItems.balanceOf(buyer, tokenId), quantity);
        
        console.log("[SUCCESS] Refund on overpayment handled correctly");
    }
}

