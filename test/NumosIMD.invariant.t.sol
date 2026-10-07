// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NumosIMD} from "../src/NumosIMD.sol";

/// @dev A closed set of holders allows the invariant to account for every minted unit.
contract NumosIMDHandler is Test {
    NumosIMD private immutable token;
    address[4] private holders = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(NumosIMD token_) {
        token = token_;
        for (uint256 i; i < holders.length; ++i) {
            expectedBalance[holders[i]] = (1_000_000_000 * 10 ** 18) / holders.length;
        }
    }

    function holder(uint256 index) public view returns (address) {
        return holders[index % holders.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = holder(fromSeed);
        address to = holder(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) public {
        address owner = holder(ownerSeed);
        address spender = holder(spenderSeed);
        amount = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) public {
        address owner = holder(ownerSeed);
        address spender = holder(spenderSeed);
        address to = holder(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        uint256 amount = bound(amountSeed, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    // Expected reverts are checked here, so fail_on_revert still catches unexpected
    // failures. The balance/allowance ghosts must survive each rejected operation.
    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) public {
        address from = holder(fromSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excessSeed, 1, type(uint256).max - balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(holder(toSeed), amount);
    }

    function transferFromAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 allowanceSeed)
        public
    {
        // Explicitly finite, including max - 1; no early return for infinite approvals.
        uint256 allowed = bound(allowanceSeed, 0, type(uint256).max - 1);
        approve(ownerSeed, spenderSeed, allowed, false);
        address spender = holder(spenderSeed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(holder(ownerSeed), holder(toSeed), allowed + 1);
    }

    function transferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 excessSeed,
        bool unlimited
    ) public {
        address owner = holder(ownerSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excessSeed, 1, type(uint256).max - balance);
        approve(ownerSeed, spenderSeed, amount, unlimited);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(holder(spenderSeed));
        token.transferFrom(owner, holder(toSeed), amount);
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) public {
        approve(ownerSeed, spenderSeed, 0, false);
        address spender = holder(spenderSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder(ownerSeed), holder(toSeed), 1);
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) public {
        address owner = holder(ownerSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        if (delegated) {
            approve(ownerSeed, spenderSeed, amount, false);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(holder(spenderSeed));
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract NumosIMDInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    NumosIMD private token;
    NumosIMDHandler private handler;

    function setUp() public {
        token = new NumosIMD();
        handler = new NumosIMDHandler(token);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.holder(i), SUPPLY / 4));
        }

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = NumosIMDHandler.transfer.selector;
        selectors[1] = NumosIMDHandler.approve.selector;
        selectors[2] = NumosIMDHandler.transferFrom.selector;
        selectors[3] = NumosIMDHandler.transferAboveBalance.selector;
        selectors[4] = NumosIMDHandler.transferFromAboveAllowance.selector;
        selectors[5] = NumosIMDHandler.transferFromAboveBalance.selector;
        selectors[6] = NumosIMDHandler.revokeAndAttemptSpend.selector;
        selectors[7] = NumosIMDHandler.transferToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.holder(i);
            uint256 balance = token.balanceOf(owner);
            sum += balance;
            assertEq(balance, handler.expectedBalance(owner));
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.holder(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(sum, SUPPLY);
    }
}
