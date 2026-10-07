// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title NumosIMD
/// @notice Fixed supply ERC-20: one billion NUMOS with 18 decimals.
/// @dev The constructor caller receives the entire supply, including when deployed by a factory.
contract NumosIMD is ERC20 {
    /// @notice Total issuance in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("NumosIMD", "NUMOS") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
