// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NumosIMD} from "src/NumosIMD.sol";

/// @dev Complements the launch and basic ERC-20 tests with allowance lifecycle and arithmetic edges.
/// forge-config: default.fuzz.runs = 1000
contract NumosIMDAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    NumosIMD private token;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new NumosIMD();
    }

    function test_OneWeiCanBeTransferredAndSpentOnlyOnce() public {
        assertTrue(token.transfer(ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);

        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferCannotOverflowBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumDelegatedTransferCannotBypassBalanceCheck() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsDecremented() public {
        uint256 allowed = type(uint256).max - 1;
        assertTrue(token.approve(SPENDER, allowed));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), allowed - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeReplacedWithFiniteApproval() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 10));
        assertTrue(token.approve(SPENDER, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 2);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(ALICE), 10);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 11);
        assertEq(token.balanceOf(address(this)), SUPPLY - 11);
    }

    function test_InfiniteApprovalCanBeRevoked() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_RefundDoesNotRestoreSpentAllowance() public {
        assertTrue(token.approve(SPENDER, 5));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 5));
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 5));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ApprovalsAreScopedToBothOwnerAndSpender() public {
        assertTrue(token.transfer(ALICE, 5));
        assertTrue(token.approve(SPENDER, 2));
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 3));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, SPENDER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 2);
        assertEq(token.allowance(ALICE, BOB), 3);

        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, BOB, 3));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), SPENDER, 2));
        assertEq(token.balanceOf(address(this)), SUPPLY - 7);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(BOB), 3);
        assertEq(token.balanceOf(SPENDER), 2);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(address(this), BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferPreservesFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(SPENDER, 5));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 0));
        assertEq(token.allowance(address(this), SPENDER), 5);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_InfiniteApprovalCannotBurnViaTransferFromToZero() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RoundTripPreservesBalancesAndApprovals(uint256 initialSeed, uint256 amountSeed, uint256 approved)
        public
    {
        uint256 initial = bound(initialSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, 0, SUPPLY - initial);
        assertTrue(token.transfer(ALICE, initial));
        assertTrue(token.approve(SPENDER, approved));

        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), amount));

        assertEq(token.balanceOf(address(this)), SUPPLY - initial);
        assertEq(token.balanceOf(ALICE), initial);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferOnlyConsumesAllowance(
        uint256 balanceSeed,
        uint256 allowanceSeed,
        uint256 amountSeed,
        bool unlimited
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : bound(allowanceSeed, 0, type(uint256).max - 1);
        uint256 amount = bound(amountSeed, 0, balance < approved ? balance : approved);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, ALICE, amount));

        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), unlimited ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovedOverspendRevertsAtomically(uint256 balanceSeed, uint256 excessSeed, bool unlimited)
        public
    {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = balance + bound(excessSeed, 1, type(uint256).max - balance);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);

        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReducedAllowanceCannotSpendOldApproval(uint256 originalSeed, uint256 reducedSeed) public {
        uint256 original = bound(originalSeed, 1, SUPPLY);
        uint256 reduced = bound(reducedSeed, 0, original - 1);
        assertTrue(token.approve(SPENDER, original));
        assertTrue(token.approve(SPENDER, reduced));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, reduced, reduced + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, reduced + 1);
        assertEq(token.allowance(address(this), SPENDER), reduced);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, reduced));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - reduced);
        assertEq(token.balanceOf(ALICE), reduced);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
