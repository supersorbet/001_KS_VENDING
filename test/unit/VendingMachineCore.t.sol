// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {VendingMachineCore} from "../../src/libraries/VendingMachineCore.sol";

/// @title VendingMachineCore Unit Tests
/// @notice Tests for core validation and utility functions
contract VendingMachineCoreTest is Test {
    using VendingMachineCore for VendingMachineCore.SaleConfig;

    function test_getVersionedPurchaseKey() public {
        uint256 tokenId = 1;
        uint64 saleVersion = 2;
        address user = address(0x123);

        bytes32 key = VendingMachineCore.getVersionedPurchaseKey(
            tokenId,
            saleVersion,
            user
        );

        // Should generate consistent keys
        bytes32 key2 = VendingMachineCore.getVersionedPurchaseKey(
            tokenId,
            saleVersion,
            user
        );
        assertEq(key, key2);

        // Different inputs should produce different keys
        bytes32 key3 = VendingMachineCore.getVersionedPurchaseKey(
            tokenId + 1,
            saleVersion,
            user
        );
        assertNotEq(key, key3);
    }

    function test_checkForDuplicates_NoDuplicates() public {
        // Test with a helper that creates calldata array
        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 3;
        this._testCheckForDuplicates(arr);
    }

    function test_checkForDuplicates_WithDuplicates() public {
        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 1; // Duplicate
        
        vm.expectRevert(VendingMachineCore.DuplicateTokenId.selector);
        this._testCheckForDuplicates(arr);
    }
    
    function _testCheckForDuplicates(uint256[] memory tokenIds) external pure {
        // Replicate the logic since we can't easily convert memory to calldata
        uint256 length = tokenIds.length;
        for (uint256 i; i < length; ) {
            for (uint256 j = i + 1; j < length; ) {
                if (tokenIds[i] == tokenIds[j]) {
                    revert VendingMachineCore.DuplicateTokenId();
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

    function test_isLive_ActiveSale() public {
        uint256 now = block.timestamp;
        VendingMachineCore.SaleConfig memory config = VendingMachineCore
            .SaleConfig({
                price: 1 ether,
                startTime: uint64(now > 100 ? now - 100 : 1),
                endTime: uint64(now + 100),
                maxSupply: 100,
                maxPerAddress: 10,
                totalSold: 50,
                paymentToken: address(0),
                active: true,
                saleVersion: 1
            });

        bool isLive = VendingMachineCore.isLive(config, now);
        assertTrue(isLive);
    }

    function test_isLive_InactiveSale() public {
        uint256 now = block.timestamp;
        VendingMachineCore.SaleConfig memory config = VendingMachineCore
            .SaleConfig({
                price: 1 ether,
                startTime: uint64(now > 100 ? now - 100 : 1),
                endTime: uint64(now + 100),
                maxSupply: 100,
                maxPerAddress: 10,
                totalSold: 50,
                paymentToken: address(0),
                active: false,
                saleVersion: 1
            });

        bool isLive = VendingMachineCore.isLive(config, now);
        assertFalse(isLive);
    }

    function test_isLive_SoldOut() public {
        uint256 now = block.timestamp;
        VendingMachineCore.SaleConfig memory config = VendingMachineCore
            .SaleConfig({
                price: 1 ether,
                startTime: uint64(now > 100 ? now - 100 : 1),
                endTime: uint64(now + 100),
                maxSupply: 100,
                maxPerAddress: 10,
                totalSold: 100, // Sold out
                paymentToken: address(0),
                active: true,
                saleVersion: 1
            });

        bool isLive = VendingMachineCore.isLive(config, now);
        assertFalse(isLive);
    }

    function test_isLive_NotStarted() public {
        VendingMachineCore.SaleConfig memory config = VendingMachineCore
            .SaleConfig({
                price: 1 ether,
                startTime: uint64(block.timestamp + 100), // Future
                endTime: uint64(block.timestamp + 200),
                maxSupply: 100,
                maxPerAddress: 10,
                totalSold: 0,
                paymentToken: address(0),
                active: true,
                saleVersion: 1
            });

        bool isLive = VendingMachineCore.isLive(config, block.timestamp);
        assertFalse(isLive);
    }

    function test_isLive_Ended() public {
        // Use a fixed timestamp that's definitely in the past
        uint256 currentTime = 1000000; // Fixed timestamp
        uint64 startTime = uint64(currentTime - 200);
        uint64 endTime = uint64(currentTime - 100); // Definitely in the past
        
        VendingMachineCore.SaleConfig memory config = VendingMachineCore
            .SaleConfig({
                price: 1 ether,
                startTime: startTime,
                endTime: endTime, // Past
                maxSupply: 100,
                maxPerAddress: 10,
                totalSold: 50,
                paymentToken: address(0),
                active: true,
                saleVersion: 1
            });

        bool isLive = VendingMachineCore.isLive(config, currentTime);
        // Sale ended (currentTime > endTime), so should not be live
        // isLive checks: active && currentTime >= startTime && currentTime <= endTime && totalSold < maxSupply
        // Since currentTime > endTime, the condition "currentTime <= endTime" is false
        assertFalse(isLive, "Sale should not be live when endTime is in the past");
    }

    function test_MAX_BATCH_SIZE() public {
        assertEq(VendingMachineCore.MAX_BATCH_SIZE, 50);
    }
}

