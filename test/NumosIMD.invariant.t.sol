// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NumosIMD} from "../src/NumosIMD.sol";

/// @dev A closed set of holders allows the invariant to account for every minted unit.
contract NumosIMDHandler is Test {
    NumosIMD private immutable token;
    address[4] private holders = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(NumosIMD token_) {
        token = token_;
        expectedBalance[holders[0]] = 1_000_000_000 * 10 ** 18;
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
}

contract NumosIMDInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    NumosIMD private token;
    NumosIMDHandler private handler;

    function setUp() public {
        token = new NumosIMD();
        handler = new NumosIMDHandler(token);
        token.transfer(handler.holder(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = NumosIMDHandler.transfer.selector;
        selectors[1] = NumosIMDHandler.approve.selector;
        selectors[2] = NumosIMDHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.holder(i);
            uint256 balance = token.balanceOf(owner);
            sum += balance;
            assertEq(balance, handler.expectedBalance(owner));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.holder(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(sum, SUPPLY);
    }
}
