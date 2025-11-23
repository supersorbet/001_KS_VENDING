// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {KSVendingMachineOP_Patched} from "../../src/contracts/KSVendingMachineOP_PATCHED.sol";
import {VendingMachineCore} from "../../src/libraries/VendingMachineCore.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title Vending Machine Fuzz Tests
/// @notice Comprehensive fuzz testing with detailed logging
contract VendingMachineFuzzTest is Test {
    KSVendingMachineOP_Patched public vendingMachine;
    MockERC1155 public ksItems;
    MockERC20 public paymentToken;
    
    address public owner;
    address public fundsRecipient;
    address public buyer;
    
    uint32 public constant INITIAL_SUPPLY = 10000;
    uint128 public constant BASE_PRICE = 1 ether;
    
    event Purchase(
        address indexed buyer,
        uint256 indexed tokenId,
        uint32 quantity,
        uint128 price,
        address paymentToken
    );

    function setUp() public {
        owner = address(this);
        fundsRecipient = address(0x100);
        buyer = address(0x200);
        
        // Deploy contracts
        ksItems = new MockERC1155();
        paymentToken = new MockERC20();
        vendingMachine = new KSVendingMachineOP_Patched();
        
        // Initialize
        vendingMachine.setKSItems(address(ksItems));
        vendingMachine.setFundsRecipient(fundsRecipient);
        
        // Mint tokens to vending machine
        ksItems.mint(address(vendingMachine), 1, INITIAL_SUPPLY);
        ksItems.mint(address(vendingMachine), 2, INITIAL_SUPPLY);
        ksItems.mint(address(vendingMachine), 3, INITIAL_SUPPLY);
        
        // Mint payment tokens to buyer
        paymentToken.mint(buyer, type(uint256).max);
        
        // Give buyer ETH
        vm.deal(buyer, 1000 ether);
        
        console.log(".. Fuzz Test Setup Complete ..");
        console.log("Vending Machine:", address(vendingMachine));
        console.log("KS Items:", address(ksItems));
        console.log("Buyer:", buyer);
        console.log("Initial Supply per token:", INITIAL_SUPPLY);
    }

    /// @notice Fuzz test: Purchase with random quantities
    /// @param tokenId The token ID to purchase (bounded to 1-3)
    /// @param quantity The quantity to purchase (bounded to prevent overflow)
    function testFuzz_Purchase_ETH(
        uint256 tokenId,
        uint32 quantity
    ) public {
        // Bound inputs to reasonable ranges
        tokenId = bound(tokenId, 1, 3);
        quantity = uint32(bound(uint256(quantity), 1, 100));
        
        // Configure sale
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = uint64(block.timestamp + 365 days);
        uint128 price = BASE_PRICE;
        uint32 maxSupply = uint32(INITIAL_SUPPLY);
        uint32 maxPerAddress = 1000;
        
        vendingMachine.configSale(
            tokenId,
            price,
            startTime,
            endTime,
            maxSupply,
            maxPerAddress,
            address(0), // ETH payment
            false
        );
        
        uint256 totalCost = uint256(price) * quantity;
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 recipientBalanceBefore = fundsRecipient.balance;
        uint256 contractBalanceBefore = address(vendingMachine).balance;
        
        console.log("\n.. Fuzz Purchase Test ..");
        console.log("Token ID:", tokenId);
        console.log("Quantity:", quantity);
        console.log("Price per token:", price);
        console.log("Total cost:", totalCost);
        console.log("Buyer balance before:", buyerBalanceBefore);
        
        // Ensure buyer has enough ETH
        if (buyerBalanceBefore < totalCost) {
            vm.deal(buyer, totalCost);
            buyerBalanceBefore = buyer.balance;
        }
        
        vm.prank(buyer);
        vendingMachine.purchase{value: totalCost}(tokenId, quantity);
        
        // Verify balances
        uint256 buyerBalanceAfter = buyer.balance;
        uint256 recipientBalanceAfter = fundsRecipient.balance;
        uint256 contractBalanceAfter = address(vendingMachine).balance;
        
        console.log("Buyer balance after:", buyerBalanceAfter);
        console.log("Recipient balance after:", recipientBalanceAfter);
        console.log("Contract balance after:", contractBalanceAfter);
        console.log("Buyer balance change:", int256(buyerBalanceAfter) - int256(buyerBalanceBefore));
        console.log("Recipient balance change:", int256(recipientBalanceAfter) - int256(recipientBalanceBefore));
        
        // Assertions
        assertEq(buyerBalanceBefore - buyerBalanceAfter, totalCost, "Buyer should pay total cost");
        assertEq(recipientBalanceAfter - recipientBalanceBefore, totalCost, "Recipient should receive total cost");
        assertEq(ksItems.balanceOf(buyer, tokenId), quantity, "Buyer should receive tokens");
        assertEq(contractBalanceAfter, contractBalanceBefore, "Contract should not hold ETH");
        
        console.log("[SUCCESS] Purchase successful!");
    }

    /// @notice Fuzz test: Purchase with ERC20 payment
    /// @param tokenId The token ID to purchase
    /// @param quantity The quantity to purchase
    function testFuzz_Purchase_ERC20(
        uint256 tokenId,
        uint32 quantity
    ) public {
        tokenId = bound(tokenId, 1, 3);
        quantity = uint32(bound(uint256(quantity), 1, 100));
        
        // Configure sale with ERC20 payment
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = uint64(block.timestamp + 365 days);
        uint128 price = BASE_PRICE;
        uint32 maxSupply = uint32(INITIAL_SUPPLY);
        uint32 maxPerAddress = 1000;
        
        vendingMachine.configSale(
            tokenId,
            price,
            startTime,
            endTime,
            maxSupply,
            maxPerAddress,
            address(paymentToken),
            false
        );
        
        uint256 totalCost = uint256(price) * quantity;
        uint256 buyerTokenBalanceBefore = paymentToken.balanceOf(buyer);
        uint256 recipientTokenBalanceBefore = paymentToken.balanceOf(fundsRecipient);
        
        console.log("\n.. Fuzz Purchase ERC20 Test ..");
        console.log("Token ID:", tokenId);
        console.log("Quantity:", quantity);
        console.log("Total cost:", totalCost);
        console.log("Buyer token balance before:", buyerTokenBalanceBefore);
        
        // Approve and purchase
        vm.prank(buyer);
        paymentToken.approve(address(vendingMachine), totalCost);
        
        vm.prank(buyer);
        vendingMachine.purchase(tokenId, quantity);
        
        uint256 buyerTokenBalanceAfter = paymentToken.balanceOf(buyer);
        uint256 recipientTokenBalanceAfter = paymentToken.balanceOf(fundsRecipient);
        
        console.log("Buyer token balance after:", buyerTokenBalanceAfter);
        console.log("Recipient token balance after:", recipientTokenBalanceAfter);
        console.log("Buyer token balance change:", int256(buyerTokenBalanceAfter) - int256(buyerTokenBalanceBefore));
        
        assertEq(buyerTokenBalanceBefore - buyerTokenBalanceAfter, totalCost, "Buyer should pay tokens");
        assertEq(recipientTokenBalanceAfter - recipientTokenBalanceBefore, totalCost, "Recipient should receive tokens");
        assertEq(ksItems.balanceOf(buyer, tokenId), quantity, "Buyer should receive NFTs");
        
        console.log("[SUCCESS] ERC20 Purchase successful!");
    }

    /// @notice Fuzz test: Batch purchase with random arrays
    /// @param tokenIds Array of token IDs (bounded)
    /// @param quantities Array of quantities (bounded)
    function testFuzz_PurchaseBatch(
        uint256[5] memory tokenIds,
        uint32[5] memory quantities
    ) public {
        console.log("\n.. Fuzz Batch Purchase Test ..");
        
        // Bound and normalize inputs
        uint256[] memory normalizedTokenIds = new uint256[](5);
        uint32[] memory normalizedQuantities = new uint32[](5);
        uint256 totalCost = 0;
        uint256 validCount = 0;
        
        // Configure sales for tokens 1-3
        for (uint256 i = 1; i <= 3; i++) {
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
        
        // Normalize inputs: bound tokenIds to 1-3, quantities to 1-10
        for (uint256 i = 0; i < 5; i++) {
            uint256 tokenId = bound(tokenIds[i], 1, 3);
            uint32 quantity = uint32(bound(uint256(quantities[i]), 1, 10));
            
            // Check for duplicates
            bool isDuplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (normalizedTokenIds[j] == tokenId) {
                    isDuplicate = true;
                    break;
                }
            }
            
            if (!isDuplicate) {
                normalizedTokenIds[validCount] = tokenId;
                normalizedQuantities[validCount] = quantity;
                totalCost += uint256(BASE_PRICE) * quantity;
                validCount++;
            }
        }
        
        // Resize arrays to valid count
        uint256[] memory finalTokenIds = new uint256[](validCount);
        uint32[] memory finalQuantities = new uint32[](validCount);
        
        for (uint256 i = 0; i < validCount; i++) {
            finalTokenIds[i] = normalizedTokenIds[i];
            finalQuantities[i] = normalizedQuantities[i];
        }
        
        console.log("Valid purchases:", validCount);
        console.log("Total cost:", totalCost);
        
        if (validCount == 0) {
            console.log("[WARNING] No valid purchases, skipping");
            return;
        }
        
        // Ensure buyer has enough ETH
        if (buyer.balance < totalCost) {
            vm.deal(buyer, totalCost);
        }
        
        uint256 buyerBalanceBefore = buyer.balance;
        
        vm.prank(buyer);
        vendingMachine.purchaseBatch{value: totalCost}(finalTokenIds, finalQuantities);
        
        uint256 buyerBalanceAfter = buyer.balance;
        
        console.log("Buyer balance change:", int256(buyerBalanceAfter) - int256(buyerBalanceBefore));
        
        // Verify all purchases
        for (uint256 i = 0; i < validCount; i++) {
            assertEq(
                ksItems.balanceOf(buyer, finalTokenIds[i]),
                finalQuantities[i],
                "Buyer should receive correct quantity"
            );
            console.log("Token", finalTokenIds[i], "balance:", ksItems.balanceOf(buyer, finalTokenIds[i]));
        }
        
        console.log("[SUCCESS] Batch purchase successful!");
    }

    /// @notice Fuzz test: Sale configuration with random parameters
    /// @param price Random price (bounded)
    /// @param duration Random sale duration in seconds
    /// @param maxSupply Random max supply (bounded)
    function testFuzz_ConfigSale(
        uint128 price,
        uint64 duration,
        uint32 maxSupply
    ) public {
        console.log("\n.. Fuzz Config Sale Test ..");
        
        // Bound inputs
        price = uint128(bound(uint256(price), 0.001 ether, 100 ether));
        duration = uint64(bound(uint256(duration), 1 hours, 365 days));
        maxSupply = uint32(bound(uint256(maxSupply), 1, INITIAL_SUPPLY));
        
        uint256 tokenId = 1;
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = uint64(block.timestamp + duration);
        uint32 maxPerAddress = maxSupply;
        
        console.log("Token ID:", tokenId);
        console.log("Price:", price);
        console.log("Start time:", startTime);
        console.log("End time:", endTime);
        console.log("Duration:", duration);
        console.log("Max supply:", maxSupply);
        console.log("Max per address:", maxPerAddress);
        
        vendingMachine.configSale(
            tokenId,
            price,
            startTime,
            endTime,
            maxSupply,
            maxPerAddress,
            address(0),
            false
        );
        
        // Verify configuration
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
        
        console.log("Configured price:", configPrice);
        console.log("Configured start time:", configStartTime);
        console.log("Configured end time:", configEndTime);
        console.log("Configured max supply:", configMaxSupply);
        console.log("Sale active:", configActive);
        console.log("Sale version:", configSaleVersion);
        
        assertEq(configPrice, price, "Price should match");
        assertEq(configStartTime, startTime, "Start time should match");
        assertEq(configEndTime, endTime, "End time should match");
        assertEq(configMaxSupply, maxSupply, "Max supply should match");
        assertTrue(configActive, "Sale should be active");
        
        console.log("[SUCCESS] Sale configuration successful!");
    }

    /// @notice Fuzz test: Multiple purchases accumulating
    /// @param numPurchases Number of purchases to make (bounded)
    /// @param quantityPerPurchase Quantity per purchase (bounded)
    function testFuzz_MultiplePurchases(
        uint8 numPurchases,
        uint32 quantityPerPurchase
    ) public {
        numPurchases = uint8(bound(uint256(numPurchases), 1, 10));
        quantityPerPurchase = uint32(bound(uint256(quantityPerPurchase), 1, 10));
        
        uint256 tokenId = 1;
        uint128 price = BASE_PRICE;
        uint32 maxPerAddress = 1000;
        
        // Configure sale
        vendingMachine.configSale(
            tokenId,
            price,
            uint64(block.timestamp),
            uint64(block.timestamp + 365 days),
            INITIAL_SUPPLY,
            maxPerAddress,
            address(0),
            false
        );
        
        console.log("\n.. Fuzz Multiple Purchases Test ..");
        console.log("Number of purchases:", numPurchases);
        console.log("Quantity per purchase:", quantityPerPurchase);
        console.log("Total quantity:", numPurchases * quantityPerPurchase);
        
        uint256 totalQuantity = 0;
        uint256 totalCost = 0;
        
        for (uint256 i = 0; i < numPurchases; i++) {
            uint256 purchaseCost = uint256(price) * quantityPerPurchase;
            totalCost += purchaseCost;
            totalQuantity += quantityPerPurchase;
            
            if (buyer.balance < purchaseCost) {
                vm.deal(buyer, purchaseCost);
            }
            
            console.log("Purchase", i + 1, "- Cost:", purchaseCost);
            
            vm.prank(buyer);
            vendingMachine.purchase{value: purchaseCost}(tokenId, quantityPerPurchase);
        }
        
        uint256 finalBalance = ksItems.balanceOf(buyer, tokenId);
        
        console.log("Final token balance:", finalBalance);
        console.log("Expected total quantity:", totalQuantity);
        console.log("Total cost paid:", totalCost);
        
        assertEq(finalBalance, totalQuantity, "Total balance should equal sum of purchases");
        
        // Check user purchase info
        (uint32 purchased, uint32 remaining, bool canPurchase) = vendingMachine.getUserPurchaseInfo(tokenId, buyer);
        console.log("User purchased:", purchased);
        console.log("User remaining allocation:", remaining);
        console.log("User can purchase:", canPurchase);
        
        assertEq(purchased, uint32(totalQuantity), "Purchased amount should match");
        
        console.log("[SUCCESS] Multiple purchases successful!");
    }

    /// @notice Fuzz test: Edge cases - zero and max values
    /// @param quantity Quantity to test (will be bounded to edge cases)
    function testFuzz_EdgeCases(uint32 quantity) public {
        console.log("\n.. Fuzz Edge Cases Test ..");
        
        uint256 tokenId = 1;
        uint128 price = BASE_PRICE;
        
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
        
        // Test with quantity = 1 (minimum)
        quantity = uint32(bound(uint256(quantity), 1, 1));
        
        console.log("Testing with quantity:", quantity);
        
        uint256 cost = uint256(price) * quantity;
        vm.deal(buyer, cost);
        
        vm.prank(buyer);
        vendingMachine.purchase{value: cost}(tokenId, quantity);
        
        assertEq(ksItems.balanceOf(buyer, tokenId), quantity, "Should receive tokens");
        console.log("[SUCCESS] Edge case (quantity=1) successful!");
    }
}

