// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/* Import statements */
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Owned} from "@solmate/auth/Owned.sol";

/**
 * @title StableCoin
 * @author Robbie Sumner
 * @notice This contract is only meant to be the ERC20 token governed/owned by SCEngine. It does not contain any logic.
 */
contract StableCoin is ERC20, Owned {
    /* Type declarations */
    /* State variables */
    /* Events */
    /* Errors */
    error StableCoin__MintToZeroAddress();
    error StableCoin__AmountZero();

    /* Modifiers */
    /* Functions */
    /// constructor
    constructor() ERC20("Stable Coin", "STBL", 18) Owned(msg.sender) {}

    /// receive function (if exists)
    /// fallback function (if exists)
    /// external
    function mint(
        address to,
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert StableCoin__MintToZeroAddress();
        }
        if (amount == 0) {
            revert StableCoin__AmountZero();
        }
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) external onlyOwner {
        if (amount == 0) {
            revert StableCoin__AmountZero();
        }
        _burn(msg.sender, amount);
    }
    /// public
    /// internal
    /// private
}
