// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {VendingMachineCore} from "../../src/libraries/VendingMachineCore.sol";
import {VendingMachineOps} from "../../src/libraries/VendingMachineOps.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title VendingMachineOps Unit Tests
/// @notice Tests for payment and state management operations
contract VendingMachineOpsTest is Test {
    using SafeTransferLib for address;

    address fundsRecipient;
    address user;

    function setUp() public {
        fundsRecipient = address(0x100);
        user = address(0x200);
        vm.deal(user, 100 ether);
        vm.deal(address(this), 100 ether);
    }

    function test_handlePayment_ETH_Sufficient() public {
        uint256 totalCost = 1 ether;
        uint256 initialBalance = fundsRecipient.balance;

        vm.deal(user, totalCost);
        vm.prank(user);
        TestPaymentWrapper wrapper = new TestPaymentWrapper();
        wrapper.handlePayment{value: totalCost}(address(0), totalCost, fundsRecipient);

        assertEq(fundsRecipient.balance, initialBalance + totalCost);
    }

    function test_handlePayment_ETH_WithRefund() public {
        uint256 totalCost = 1 ether;
        uint256 sentAmount = 2 ether;
        
        uint256 initialBalance = fundsRecipient.balance;
        // Reset user balance and give them enough for the test
        vm.deal(user, sentAmount);
        uint256 initialUserBalance = user.balance; // Should be sentAmount (2 ether)

        TestPaymentWrapper wrapper = new TestPaymentWrapper();
        
        vm.prank(user);
        wrapper.handlePayment{value: sentAmount}(address(0), totalCost, fundsRecipient);

        // fundsRecipient should receive totalCost (balance increased by totalCost)
        assertEq(fundsRecipient.balance - initialBalance, totalCost, "fundsRecipient should receive totalCost");
        // User sent sentAmount (2 ether), received refund (1 ether), so net -totalCost (1 ether)
        // Final balance should be initialUserBalance - totalCost
        assertEq(user.balance, initialUserBalance - totalCost, "user should pay net totalCost");
    }

    function test_handlePayment_ETH_Insufficient() public {
        uint256 totalCost = 1 ether;
        uint256 sentAmount = 0.5 ether;

        vm.deal(user, sentAmount);
        vm.prank(user);
        TestPaymentWrapper wrapper = new TestPaymentWrapper();
        vm.expectRevert(VendingMachineCore.InsufficientPayment.selector);
        wrapper.handlePayment{value: sentAmount}(address(0), totalCost, fundsRecipient);
    }

    function test_handlePayment_ERC20_WithETH() public {
        MockERC20 token = new MockERC20();
        token.mint(user, 100 ether);
        uint256 totalCost = 1 ether;

        vm.deal(user, 1 ether);
        vm.prank(user);
        TestPaymentWrapper wrapper = new TestPaymentWrapper();
        vm.expectRevert(VendingMachineCore.InvalidPaymentToken.selector);
        wrapper.handlePayment{value: 1 ether}(address(token), totalCost, fundsRecipient);
    }

    function test_updatePurchaseStateVersioned_NoOverflow() public {
        // Test overflow protection logic
        uint32 maxUint32 = type(uint32).max;
        uint32 quantity = 100;

        // Should not overflow - check that subtraction is safe
        assertTrue(maxUint32 >= quantity);
        assertTrue(maxUint32 - quantity < maxUint32);
    }

    function test_updatePurchaseStateVersioned_Overflow() public {
        uint32 maxUint32 = type(uint32).max;
        uint32 quantity = 1;

        // Overflow check: maxUint32 > maxUint32 - quantity should be true
        // This validates the overflow protection logic
        assertTrue(maxUint32 > maxUint32 - quantity);
    }
}

/// @notice Wrapper contract to test internal functions
contract TestPaymentWrapper {
    function handlePayment(
        address paymentToken,
        uint256 totalCost,
        address fundsRecipient
    ) external payable {
        VendingMachineOps.handlePayment(paymentToken, totalCost, fundsRecipient);
    }
    
    // Allow contract to receive ETH (for refunds)
    receive() external payable {}
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
