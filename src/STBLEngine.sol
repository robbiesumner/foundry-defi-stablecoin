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
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
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
    event CollateralWithdrawal(address indexed from, address indexed to, address indexed token, uint256 amount);

    /* Errors */
    error STBLEngine__LengthOfTokensAndPriceFeedsDoNotMatch();
    error STBLEngine__AmountZero();
    error STBLEngine__TokenNotAllowed(address token);
    error STBLEngine__TransferFailed();
    error STBLEngine__BadHealthFactor();
    error STBLEngine__GoodHealthFactor();
    error STBLEngine__HealthFactorNotImproved();

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
     * @param stblAmount The amount of `StableCoin` to burn
     * @param collateralAmount The amount of `collateralToken` to withdraw
     */
    function burnStblAndWithdrawCollateral(address collateralToken, uint256 stblAmount, uint256 collateralAmount)
        external
    {
        burnStbl(stblAmount);
        withdraw(collateralToken, collateralAmount);
    }

    /**
     * This function lets the user liquidate another user's position.
     * @param user The address of the user to liquidate
     * @param collateralToken The address of the ERC20 token to withdraw
     */
    function liquidate(address user, address collateralToken, uint256 coveredDebt)
        external
        moreThanZero(coveredDebt)
        nonReentrant
    {
        uint256 healthFactor = getHealthFactor(user);
        if (healthFactor >= MIN_HEALTH_FACTOR) {
            revert STBLEngine__GoodHealthFactor();
        }

        uint256 tokenAmount = getTokenValue(collateralToken, coveredDebt);
        uint256 bonus = tokenAmount * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;

        _withdraw(collateralToken, tokenAmount + bonus, user, msg.sender);
        _burnStbl(msg.sender, user, coveredDebt);

        if (getHealthFactor(user) <= healthFactor) {
            revert STBLEngine__HealthFactorNotImproved();
        }
    }

    function getUserInformation(address user) external view returns (uint256 dscMinted, uint256 collateralValue) {
        dscMinted = s_stblMinted[user];
        collateralValue = getCollateralValue(user);
    }

    function getStblAddress() external view returns (address) {
        return address(i_STBL);
    }

    function getCollateralAmount(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getValidCollateralTokens() external view returns (address[] memory) {
        return s_tokens;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
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
        _withdraw(token, amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBad(msg.sender);
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
    function burnStbl(uint256 amount) public moreThanZero(amount) {
        _burnStbl(msg.sender, msg.sender, amount);
    }

    /**
     * This function returns the health factor of the user. It should be greater than 1.
     * @param user The address of the user
     * @return healthFactor The ratio of the total collateral value deposited by the user to the total amount of `StableCoin` minted by the user.
     */
    function getHealthFactor(address user) public view returns (uint256 healthFactor) {
        if (s_stblMinted[user] == 0) return type(uint256).max;

        uint256 collateralAdjusted =
            getCollateralValue(user) * LIQUIDATION_THRESHOLD * PRECISION / LIQUIDATION_PRECISION;
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
            collateralValue += getUsdValue(token, s_collateralDeposited[user][token]);
        }
    }

    /**
     * This function gets the value of `amount` of `token` in us dollars.
     * @param token The address of the ERC20 token
     * @param amount The amount of `token`
     * @return usdValue The value of `amount` of `token` in us dollars
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        uint8 decimals = priceFeed.decimals();
        (, int256 price,,,) = priceFeed.latestRoundData();

        usdValue = (amount * (uint256(price) * 10 ** (18 - decimals))) / (PRECISION);
    }

    function getTokenValue(address token, uint256 usdAmount) public view returns (uint256 tokenValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        uint8 decimals = priceFeed.decimals();
        (, int256 price,,,) = priceFeed.latestRoundData();

        tokenValue = (usdAmount * (PRECISION)) / (uint256(price) * 10 ** (18 - decimals));
    }

    /// internal
    function _burnStbl(address burnedBy, address onBehalfOf, uint256 amount) internal {
        s_stblMinted[onBehalfOf] -= amount;

        bool s = i_STBL.transferFrom(burnedBy, address(this), amount);
        if (!s) {
            revert STBLEngine__TransferFailed();
        }
        i_STBL.burn(amount);
    }

    function _withdraw(address token, uint256 amount, address from, address to) internal {
        s_collateralDeposited[from][token] -= amount;
        emit CollateralWithdrawal(from, to, token, amount);

        bool s = IERC20(token).transfer(to, amount);
        if (!s) {
            revert STBLEngine__TransferFailed();
        }
    }

    /**
     * This function checks if the user has a good enough ratio of collateral to `StableCoin` minted.
     * @param user The address of the user
     */
    function revertIfHealthFactorIsBad(address user) internal view {
        uint256 userHealthFactor = getHealthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert STBLEngine__BadHealthFactor();
        }
    }
}
