// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {StableCoin} from "./StableCoin.sol";
import {ReentrancyGuard} from "@solmate/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title STBLEngine
 * @author Robbie Sumner
 * @notice This contract is the engine for the StableCoin. It owns the `StableCoin` and is the only contract that can mint/burn it. It handles the logic for depositing/withdrawing collateral and keeping the invariant 1 token == 1€.
 * @notice This contract has been written following along with Patrick Collins' Course: https://www.youtube.com/watch?v=wUjYK5gwNZs. It is loosely based on the MakerDAO DSS (DAI).
 * @dev This stablecoin has the properties:
 *      - Exogenous collateral
 *      - Pegged to the US Dollar
 *      - Algorithmic (not by governance)
 */
contract STBLEngine is ReentrancyGuard {
    /* Type declarations */

    /* State variables */
    uint256 private constant LIQUIDATION_THRESHOLD = 2; // 200% collateralization ratio
    StableCoin private immutable i_STBL;

    /// @dev this array stores the addresses of the allowed collateral tokens
    address[] private s_tokens;

    /// @dev this mapping stores the price feed addresses for the allowed collateral tokens
    mapping(address token => address priceFeeds) private s_priceFeeds;

    /// @dev this mapping stores the amount of collateral deposited by each user for each token
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    mapping(address user => uint256) private s_stblMinted;

    /* Events */
    event CollateralDeposit(address indexed user, address indexed token, uint256 amount);

    /* Errors */
    error STBLEngine__LengthOfTokensAndPriceFeedsDoNotMatch();
    error STBLEngine__AmountZero();
    error STBLEngine__TokenNotAllowed(address token);
    error STBLEngine__TransferFailed();
    error STBLEngine__RatioBelowThreshold();

    /* Modifiers */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert STBLEngine__AmountZero();
        }
        _;
    }

    modifier onlyAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert STBLEngine__TokenNotAllowed(token);
        }
        _;
    }

    /* Functions */

    /// constructor
    constructor(address[] memory tokens, address[] memory priceFeeds) {
        if (tokens.length != priceFeeds.length) {
            revert STBLEngine__LengthOfTokensAndPriceFeedsDoNotMatch();
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            s_priceFeeds[tokens[i]] = priceFeeds[i];
            s_tokens.push(tokens[i]);
        }
        i_STBL = new StableCoin();
    }

    /// receive function (if exists)
    /// fallback function (if exists)
    /// external

    /**
     * This function lets the user deposit collateral into the contract.
     * @param token The address of the ERC20 token to deposit
     * @param amount The amount of `token` to deposit
     */
    function deposit(address token, uint256 amount)
        external
        onlyAllowedToken(token)
        moreThanZero(amount)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][token] += amount;
        emit CollateralDeposit(msg.sender, token, amount);

        bool s = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!s) {
            revert STBLEngine__TransferFailed();
        }
    }

    function withdraw() external {}

    /**
     * This function lets the user mint `StableCoin`.
     * @notice The user must have more collateral deposited than the minimum threshold.
     * @param amount The amount of `StableCoin` to mint
     */
    function mintSTBL(uint256 amount) external moreThanZero(amount) nonReentrant {
        s_stblMinted[msg.sender] += amount;
        if (!hasGoodRatio(msg.sender)) {
            revert STBLEngine__RatioBelowThreshold();
        }

        bool s = i_STBL.mint(msg.sender, amount);
        if (!s) {
            revert STBLEngine__TransferFailed();
        }
    }

    function burnSTBL() external {}

    function liquidate() external {}

    /// public
    /**
     * This function gets the ratio of the total collateral value deposited by the user to the total amount of `StableCoin` minted by the user.
     * @param user The address of the user
     * @return ratio The ratio of the total collateral value deposited by the user to the total amount of `StableCoin` minted by the user
     */
    function getCollateralToStableCoinRatio(address user) public view returns (uint256 ratio) {
        uint256 collateralValue = getCollateralValue(user);
        uint256 stblMinted = s_stblMinted[user];

        ratio = collateralValue / stblMinted;
    }

    /**
     * This function gets the value of the total collateral value deposited by the user in euros.
     * @param user The address of the user
     * @return collateralValue The value of the total collateral value deposited by the user in euros
     */
    function getCollateralValue(address user) public view returns (uint256 collateralValue) {
        for (uint256 i = 0; i < s_tokens.length; i++) {
            address token = s_tokens[i];
            collateralValue += _euroValue(token, s_collateralDeposited[user][token]);
        }
    }

    /// internal
    /**
     * This function gets the value of `amount` of `token` in euros.
     * @param token The address of the ERC20 token
     * @param amount The amount of `token`
     * @return euroValue The value of `amount` of `token` in euros
     */
    function _euroValue(address token, uint256 amount) internal view returns (uint256 euroValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        uint8 decimals = priceFeed.decimals();
        (, int256 price,,,) = priceFeed.latestRoundData();

        euroValue = (amount * (uint256(price) * 10 ** (18 - decimals))) / (10e18);
    }

    /**
     * This function checks if the user has a ratio that satisfies the minimum threshold.
     * @param user The address of the user to check for
     * @return bool Whether the user has a ratio that satisfies the minimum threshold
     */
    function hasGoodRatio(address user) internal view returns (bool) {
        return getCollateralToStableCoinRatio(user) >= LIQUIDATION_THRESHOLD;
    }

    /// private
}
