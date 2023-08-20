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
    StableCoin private immutable i_STBL;

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;

    /// @dev this array stores the addresses of the allowed collateral tokens
    address[] private s_tokens;
    /// @dev this mapping stores the price feed addresses for the allowed collateral tokens
    mapping(address token => address priceFeeds) private s_priceFeeds;
    /// @dev this mapping stores the amount of collateral deposited by each user for each token
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    /// @dev this mapping stores the amount of `StableCoin` minted by each user
    mapping(address user => uint256) private s_stblMinted;

    /* Events */
    event CollateralDeposit(address indexed user, address indexed token, uint256 amount);
    event CollateralWithdrawal(address indexed user, address indexed token, uint256 amount);

    /* Errors */
    error STBLEngine__LengthOfTokensAndPriceFeedsDoNotMatch();
    error STBLEngine__AmountZero();
    error STBLEngine__TokenNotAllowed(address token);
    error STBLEngine__TransferFailed();
    error STBLEngine__BadHealthFactor(uint256 healthFactor);
    error STBLEngine__GoodHealthFactor(uint256 healthFactor);

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

    /// external
    /**
     * This function lets the user deposit collateral and mint `StableCoin` in only one transaction.
     * @param collateralToken The address of the ERC20 token to deposit
     * @param collateralAmount The amount of `collateralToken` to deposit
     * @param stblAmount The amount of `StableCoin` to mint
     */
    function depositCollateralAndMintStbl(address collateralToken, uint256 collateralAmount, uint256 stblAmount)
        external
    {
        deposit(collateralToken, collateralAmount);
        mintStbl(stblAmount);
    }

    /**
     * This function lets the user burn `StableCoin` and withdraw collateral in only one transaction.
     * @param collateralToken The address of the ERC20 token to withdraw
     * @param collateralAmount The amount of `collateralToken` to withdraw
     * @param stblAmount The amount of `StableCoin` to burn
     */
    function burnStblAndWithdrawCollateral(address collateralToken, uint256 collateralAmount, uint256 stblAmount)
        external
    {
        burnSTBL(stblAmount);
        withdraw(collateralToken, collateralAmount);
    }

    /**
     * This function lets the user liquidate another user's position.
     * @param collateralToken The address of the ERC20 token to withdraw
     * @param user The address of the user to liquidate
     */
    function liquidate(address collateralToken, address user) external nonReentrant {
        uint256 healthFactor = getHealthFactor(user);
        if (healthFactor > MIN_HEALTH_FACTOR) {
            revert STBLEngine__GoodHealthFactor(healthFactor);
        }
        // TODO: finish function
    }

    function getStblAddress() external view returns (address) {
        return address(i_STBL);
    }

    /// public
    /**
     * This function lets the user deposit collateral into the contract.
     * @param token The address of the ERC20 token to deposit
     * @param amount The amount of `token` to deposit
     */
    function deposit(address token, uint256 amount) public onlyAllowedToken(token) moreThanZero(amount) nonReentrant {
        s_collateralDeposited[msg.sender][token] += amount;
        emit CollateralDeposit(msg.sender, token, amount);

        bool s = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!s) {
            revert STBLEngine__TransferFailed();
        }
    }

    /**
     * This function lets the user withdraw collateral deposited into the contract.
     * @param token The address of the ERC20 token to withdraw
     * @param amount The amount of `token` to withdraw
     */
    function withdraw(address token, uint256 amount) public moreThanZero(amount) nonReentrant {
        s_collateralDeposited[msg.sender][token] -= amount;
        emit CollateralWithdrawal(msg.sender, token, amount);
        revertIfHealthFactorIsBad(msg.sender);

        bool s = IERC20(token).transfer(msg.sender, amount);
        if (!s) {
            revert STBLEngine__TransferFailed();
        }
    }

    /**
     * This function lets the user mint `StableCoin`.
     * @notice The user must have more collateral deposited than the minimum threshold.
     * @param amount The amount of `StableCoin` to mint
     */
    function mintStbl(uint256 amount) public moreThanZero(amount) nonReentrant {
        s_stblMinted[msg.sender] += amount;
        revertIfHealthFactorIsBad(msg.sender);

        bool s = i_STBL.mint(msg.sender, amount);
        if (!s) {
            revert STBLEngine__TransferFailed();
        }
    }

    /**
     * This function lets the user burn `StableCoin`.
     * @param amount The amount of `StableCoin` to burn
     */
    function burnSTBL(uint256 amount) public moreThanZero(amount) {
        s_stblMinted[msg.sender] -= amount;

        bool s = i_STBL.transferFrom(msg.sender, address(this), amount);
        if (!s) {
            revert STBLEngine__TransferFailed();
        }
        i_STBL.burn(amount);
    }

    /**
     * This function returns the health factor of the user. It should be greater than 1.
     * @param user The address of the user
     * @return healthFactor The ratio of the total collateral value deposited by the user to the total amount of `StableCoin` minted by the user.
     */
    function getHealthFactor(address user) public view returns (uint256 healthFactor) {
        uint256 collateralAdjusted = (getCollateralValue(user) * LIQUIDATION_THRESHOLD) * PRECISION / 100;
        healthFactor = collateralAdjusted / s_stblMinted[user];
    }

    /**
     * This function gets the value of the total collateral value deposited by the user in us dollars.
     * @param user The address of the user
     * @return collateralValue The value of the total collateral value deposited by the user in us dollars
     */
    function getCollateralValue(address user) public view returns (uint256 collateralValue) {
        for (uint256 i = 0; i < s_tokens.length; i++) {
            address token = s_tokens[i];
            collateralValue += _usdValue(token, s_collateralDeposited[user][token]);
        }
    }

    /// internal
    /**
     * This function checks if the user has a good enough ratio of collateral to `StableCoin` minted.
     * @param user The address of the user
     */
    function revertIfHealthFactorIsBad(address user) internal view {
        uint256 userHealthFactor = getHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert STBLEngine__BadHealthFactor(userHealthFactor);
        }
    }

    /**
     * This function gets the value of `amount` of `token` in us dollars.
     * @param token The address of the ERC20 token
     * @param amount The amount of `token`
     * @return usdValue The value of `amount` of `token` in us dollars
     */
    function _usdValue(address token, uint256 amount) internal view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        uint8 decimals = priceFeed.decimals();
        (, int256 price,,,) = priceFeed.latestRoundData();

        usdValue = (amount * (uint256(price) * 10 ** (18 - decimals))) / (10e18);
    }
}
