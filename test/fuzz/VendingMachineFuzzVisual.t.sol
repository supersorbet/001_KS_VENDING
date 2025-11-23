// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {KSVendingMachineOP_Patched} from "../../src/contracts/KSVendingMachineOP_PATCHED.sol";
import {VendingMachineCore} from "../../src/libraries/VendingMachineCore.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title Visual Vending Machine Fuzz Tests with Detailed Logging
/// @notice Watch Foundry generate random inputs and test your contract!
contract VendingMachineFuzzVisualTest is Test {
    KSVendingMachineOP_Patched public vendingMachine;
    MockERC1155 public ksItems;
    MockERC20 public paymentToken;
    
    address public owner;
    address public fundsRecipient;
    address public buyer;
    
    uint32 public constant INITIAL_SUPPLY = 10000;
    uint128 public constant BASE_PRICE = 1 ether;
    
    uint256 public fuzzRunCounter;

    function setUp() public {
        owner = address(this);
        fundsRecipient = address(0x100);
        buyer = address(0x200);
        
        ksItems = new MockERC1155();
        paymentToken = new MockERC20();
        vendingMachine = new KSVendingMachineOP_Patched();
        
        vendingMachine.setKSItems(address(ksItems));
        vendingMachine.setFundsRecipient(fundsRecipient);
        
        // Mint tokens
        ksItems.mint(address(vendingMachine), 1, INITIAL_SUPPLY);
        ksItems.mint(address(vendingMachine), 2, INITIAL_SUPPLY);
        ksItems.mint(address(vendingMachine), 3, INITIAL_SUPPLY);
        
        paymentToken.mint(buyer, 1000000 ether);
        vm.deal(buyer, 10000 ether);
    }

    /// @notice Watch Foundry generate random token IDs and quantities!
    /// @param rawTokenId Random token ID from Foundry (will be bounded)
    /// @param rawQuantity Random quantity from Foundry (will be bounded)
    function testFuzz_Purchase_Visual(
        uint256 rawTokenId,
        uint32 rawQuantity
    ) public {
        fuzzRunCounter++;
        
        console.log("\n");
        console.log("========================================");
        console.log("  FUZZ TEST RUN #", fuzzRunCounter);
        console.log("========================================");
        
        // Show what Foundry generated BEFORE bounding
        console.log("\n>>> FOUNDRY GENERATED (Raw Random Values):");
        console.log("   Raw tokenId:", rawTokenId);
        console.log("   Raw quantity:", rawQuantity);
        
        // Bound inputs to reasonable ranges
        uint256 tokenId = bound(rawTokenId, 1, 3);
        uint32 quantity = uint32(bound(uint256(rawQuantity), 1, 100));
        
        console.log("\n>>> AFTER BOUNDING (Valid Range):");
        console.log("   Token ID (bounded to 1-3):");
        console.log(tokenId);
        console.log("   Quantity (bounded to 1-100):");
        console.log(quantity);
        
        // Configure sale
        uint64 startTime = uint64(block.timestamp);
        uint64 endTime = uint64(block.timestamp + 365 days);
        
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
        
        uint256 totalCost = uint256(BASE_PRICE) * quantity;
        
        console.log("\n>>> TEST EXECUTION:");
        console.log("   Price per token:", BASE_PRICE);
        console.log("   Total cost:", totalCost);
        console.log("   Buyer balance before:", buyer.balance);
        
        // Ensure buyer has enough ETH
        if (buyer.balance < totalCost) {
            vm.deal(buyer, totalCost);
            console.log("   >>> Topped up buyer balance to:", buyer.balance);
        }
        
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 recipientBalanceBefore = fundsRecipient.balance;
        
        vm.prank(buyer);
        vendingMachine.purchase{value: totalCost}(tokenId, quantity);
        
        uint256 buyerBalanceAfter = buyer.balance;
        uint256 recipientBalanceAfter = fundsRecipient.balance;
        
        console.log("\n>>> RESULTS:");
        console.log("   Buyer balance after:", buyerBalanceAfter);
        console.log("   Buyer paid:", buyerBalanceBefore - buyerBalanceAfter);
        console.log("   Recipient received:", recipientBalanceAfter - recipientBalanceBefore);
        console.log("   Tokens received:");
        console.log(ksItems.balanceOf(buyer, tokenId));
        
        console.log("\n>>> VALIDATION:");
        assertEq(buyerBalanceBefore - buyerBalanceAfter, totalCost, "Buyer should pay total cost");
        assertEq(recipientBalanceAfter - recipientBalanceBefore, totalCost, "Recipient should receive total cost");
        assertEq(ksItems.balanceOf(buyer, tokenId), quantity, "Buyer should receive tokens");
        
        console.log("   [SUCCESS] All assertions passed!");
        console.log("\n>>> This was ONE of many random test cases!");
        console.log(">>> Foundry will run this with DIFFERENT random inputs!");
    }

    /// @notice Watch Foundry test with random prices!
    /// @param rawPrice Random price from Foundry
    /// @param rawQuantity Random quantity from Foundry
    function testFuzz_RandomPrices_Visual(
        uint256 rawPrice,
        uint32 rawQuantity
    ) public {
        fuzzRunCounter++;
        
        console.log("\n");
        console.log("========================================");
        console.log("  FUZZ TEST: Random Prices - Run #", fuzzRunCounter);
        console.log("========================================");
        
        // Bound price to a wide but reasonable range
        uint128 price = uint128(bound(rawPrice, 0.001 ether, 100 ether));
        uint32 quantity = uint32(bound(uint256(rawQuantity), 1, 50));
        
        console.log("\n>>> FOUNDRY GENERATED:");
        console.log("   Raw price:", rawPrice);
        console.log("   Raw quantity:", rawQuantity);
        
        console.log("\n>>> AFTER BOUNDING:");
        console.log("   Price (wei):");
        console.log(price);
        uint256 priceEtherApprox = price / 1e18;
        console.log("   Price (ether approx):");
        console.log(priceEtherApprox);
        console.log("   Quantity:");
        console.log(quantity);
        
        uint256 tokenId = 1;
        uint256 totalCost = uint256(price) * quantity;
        
        console.log("\n>>> CALCULATION:");
        console.log("   Total cost (wei):");
        console.log(totalCost);
        uint256 costEther = totalCost / 1e18;
        console.log("   Total cost (ether approx):");
        console.log(costEther);
        
        // Configure sale with random price
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
        
        vm.deal(buyer, totalCost);
        
        vm.prank(buyer);
        vendingMachine.purchase{value: totalCost}(tokenId, quantity);
        
        console.log("\n>>> RESULT:");
        console.log("   [SUCCESS] Purchase successful with random price:", price);
        console.log("   [SUCCESS] Foundry tested a different price scenario!");
    }

    /// @notice Watch Foundry test batch purchases with random arrays!
    /// @param rawTokenIds Raw random token IDs array
    /// @param rawQuantities Raw random quantities array
    function testFuzz_BatchPurchase_Visual(
        uint256[3] memory rawTokenIds,
        uint32[3] memory rawQuantities
    ) public {
        fuzzRunCounter++;
        
        console.log("\n");
        console.log("========================================");
        console.log("  FUZZ TEST: Batch Purchase - Run #", fuzzRunCounter);
        console.log("========================================");
        
        console.log("\n>>> FOUNDRY GENERATED (Raw Arrays):");
        console.log("   Raw tokenIds:");
        console.log(rawTokenIds[0]);
        console.log(rawTokenIds[1]);
        console.log(rawTokenIds[2]);
        console.log("   Raw quantities:");
        console.log(rawQuantities[0]);
        console.log(rawQuantities[1]);
        console.log(rawQuantities[2]);
        
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
        
        // Normalize arrays: bound tokenIds to 1-3, quantities to 1-10
        uint256[] memory tokenIds = new uint256[](3);
        uint32[] memory quantities = new uint32[](3);
        uint256 totalCost = 0;
        uint256 validCount = 0;
        
        console.log("\n>>> PROCESSING RANDOM ARRAYS:");
        
        for (uint256 i = 0; i < 3; i++) {
            uint256 tokenId = bound(rawTokenIds[i], 1, 3);
            uint32 quantity = uint32(bound(uint256(rawQuantities[i]), 1, 10));
            
            // Check for duplicates
            bool isDuplicate = false;
            for (uint256 j = 0; j < i; j++) {
                if (tokenIds[j] == tokenId) {
                    isDuplicate = true;
                    break;
                }
            }
            
            if (!isDuplicate) {
                tokenIds[validCount] = tokenId;
                quantities[validCount] = quantity;
                totalCost += uint256(BASE_PRICE) * quantity;
                validCount++;
                
                console.log("   Item");
                console.log(validCount);
                console.log("- Token ID:");
                console.log(tokenId);
                console.log("Quantity:");
                console.log(quantity);
            } else {
                console.log("   Item SKIPPED (duplicate token ID):");
                console.log(tokenId);
            }
        }
        
        console.log("\n>>> FINAL BATCH:");
        console.log("   Valid items:", validCount);
        console.log("   Total cost:", totalCost);
        
        if (validCount == 0) {
                console.log("   [WARNING] No valid purchases, skipping");
            return;
        }
        
        // Resize arrays
        uint256[] memory finalTokenIds = new uint256[](validCount);
        uint32[] memory finalQuantities = new uint32[](validCount);
        
        for (uint256 i = 0; i < validCount; i++) {
            finalTokenIds[i] = tokenIds[i];
            finalQuantities[i] = quantities[i];
        }
        
        vm.deal(buyer, totalCost);
        
        console.log("\n>>> EXECUTING BATCH PURCHASE:");
        vm.prank(buyer);
        vendingMachine.purchaseBatch{value: totalCost}(finalTokenIds, finalQuantities);
        
        console.log("\n>>> RESULTS:");
        for (uint256 i = 0; i < validCount; i++) {
            console.log("   Token ID:");
            console.log(finalTokenIds[i]);
            console.log("   Balance:");
            console.log(ksItems.balanceOf(buyer, finalTokenIds[i]));
        }
        
        console.log("\n>>> [SUCCESS] Batch purchase successful with random arrays!");
        console.log(">>> Foundry generated different arrays each run!");
    }

    /// @notice Watch Foundry find edge cases with random quantities!
    /// @param rawQuantity Random quantity from Foundry
    function testFuzz_EdgeCaseQuantities_Visual(uint32 rawQuantity) public {
        fuzzRunCounter++;
        
        console.log("\n");
        console.log("========================================");
        console.log("  FUZZ TEST: Edge Case Quantities - Run #", fuzzRunCounter);
        console.log("========================================");
        
        console.log("\n>>> FOUNDRY GENERATED:");
        console.log("   Raw quantity:", rawQuantity);
        
        // Bound to find edge cases
        uint32 quantity = uint32(bound(uint256(rawQuantity), 1, 100));
        
        console.log("\n>>> AFTER BOUNDING:");
        console.log("   Quantity:", quantity);
        
        // Identify edge cases
        if (quantity == 1) {
            console.log("   [EDGE CASE] Minimum quantity (1)");
        } else if (quantity == 100) {
            console.log("   [EDGE CASE] Maximum quantity (100)");
        } else if (quantity == 2) {
            console.log("   [EDGE CASE] Near minimum (2)");
        } else if (quantity == 99) {
            console.log("   [EDGE CASE] Near maximum (99)");
        } else if (quantity == 50) {
            console.log("   [EDGE CASE] Middle value (50)");
        }
        
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
        
        uint256 cost = uint256(BASE_PRICE) * quantity;
        vm.deal(buyer, cost);
        
        vm.prank(buyer);
        vendingMachine.purchase{value: cost}(tokenId, quantity);
        
        console.log("\n>>> [SUCCESS] Purchase successful!");
        console.log(">>> Foundry tested quantity:", quantity);
    }
}

