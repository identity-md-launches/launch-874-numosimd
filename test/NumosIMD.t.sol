// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NumosIMD} from "../src/NumosIMD.sol";

contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (NumosIMD) {
        return new NumosIMD{salt: salt}();
    }
}

contract NumosIMDTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    NumosIMD private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new NumosIMD();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "NumosIMD");
        assertEq(token.symbol(), "NUMOS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsSingleMint() public {
        vm.recordLogs();
        NumosIMD fresh = new NumosIMD();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_Create2MintsEntireSupplyToFactory() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        bytes32 salt = keccak256("NumosIMD factory test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(NumosIMD).creationCode))
                    )
                )
            )
        );
        NumosIMD launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    /// @dev Tests token-side exact accounting, not an implementation of a liquidity pool.
    function test_FactoryDistributionClaimsAndPoolTransfersArriveWhole() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        NumosIMD launched = factory.deploy(bytes32(uint256(1)));
        address distributor = address(0xD157);
        address pool = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 seed = SUPPLY / 4;
        uint256 remainder = SUPPLY - swarm - seed;

        vm.startPrank(address(factory));
        assertTrue(launched.transfer(distributor, swarm));
        assertTrue(launched.transfer(pool, seed));
        assertTrue(launched.transfer(ALICE, remainder));
        vm.stopPrank();
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(pool), seed);
        assertEq(launched.balanceOf(ALICE), remainder);

        vm.prank(distributor);
        assertTrue(launched.transfer(BOB, swarm));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(BOB), swarm);

        vm.prank(pool);
        assertTrue(launched.transfer(SPENDER, 100 ether));
        assertEq(launched.balanceOf(SPENDER), 100 ether);
        vm.prank(SPENDER);
        assertTrue(launched.transfer(pool, 100 ether));
        assertEq(launched.balanceOf(SPENDER), 0);
        assertEq(launched.balanceOf(pool), seed);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferReturnsTrueAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 42 ether);
        assertTrue(token.transfer(ALICE, 42 ether));
        assertEq(token.balanceOf(ALICE), 42 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 42 ether);
    }

    function test_TransferEntireBalance() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndOverwritesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 20 ether);
        assertTrue(token.approve(SPENDER, 20 ether));
        assertEq(token.allowance(address(this), SPENDER), 20 ether);
        assertTrue(token.approve(SPENDER, 5 ether));
        assertEq(token.allowance(address(this), SPENDER), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 20 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 8 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 8 ether));
        assertEq(token.allowance(address(this), SPENDER), 12 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 12 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 8 ether);
        assertEq(token.balanceOf(BOB), 12 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_DelegatedSelfTransferConsumesAllowanceOnly() public {
        token.approve(SPENDER, 5 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 5 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_RevokeAllowanceBlocksSpending() public {
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_DeployerCannotSpendHolderFundsWithoutApproval() public {
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 1 ether);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1 ether));
    }

    function test_TransferFromByHolderStillRequiresApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_RevertTransferToZeroIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertApproveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_RevertTransferFromZeroSender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_RevertTransferFromToZeroRestoresAllowance() public {
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertInsufficientBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10 ether);
        assertEq(token.allowance(ALICE, SPENDER), 10 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoMintBurnOrAdministrativeEntrypoints() public {
        token.transfer(ALICE, 10 ether);
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1 ether);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[7] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[8] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[11] = abi.encodeWithSignature("initialize(address)", BOB);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess, "deployer accessed unsupported function");
            vm.prank(BOB);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess, "stranger accessed unsupported function");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
    }

    function test_RejectsNativeCurrencyAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool paid,) = address(token).call{value: 1 ether}("");
        assertFalse(paid);
        (bool unknown,) = address(token).call(hex"deadbeef");
        assertFalse(unknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeContainsNoPrivilegedOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_TransfersConserveSupply(uint256 rawAmount, address recipient) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromConservesSupplyAndAllowance(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approved);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertTransferAboveBalance(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = balance + bound(rawExcess, 1, type(uint256).max - balance);
        token.transfer(ALICE, balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertTransferFromAboveAllowance(uint256 rawAllowance) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY - 1);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, approved + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, approved + 1);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
