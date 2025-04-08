// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { IKeeper } from "./interfaces/IKeeper.sol";
import { IRouter } from "./interfaces/IRouter.sol";
import { ITradeFacet } from "./interfaces/ITradeFacet.sol";
import { IViewFacet } from "./interfaces/IViewFacet.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "hardhat/console.sol";

/// @title Keeper
/// @notice Manages fee distribution, liquidation, and protocol treasury for trading operations.
/// @dev
///     - Handles distribution of trading and borrowing fees.
///     - Manages protocol treasury and referral earnings.
contract Keeper is IKeeper, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    uint256 public grandTotalFeesCollected; // Grand Total Fees collected, // tradeFees + borrowFees
    uint256 public totalLiquidationFeesCollected; // Total Liquidation Fees collected
    uint256 public totalLpFeesCollected; // Total Lp fees coolected (45% of trade fees + 80% of borrowing fees)
    address public usdc; // Address of the USDC token contract
    address public diamond; // Address of the diamond contract
    address public protocolTreasury; // Address of the protocol treasury
    address public insurance; // Address of the Insurance contract
    TradeFeeDistribution public tradeFeeDistribution; // Distribution percentages for trading fees
    BorrowingFeeDistribution public borrowingFeeDistribution; // Distribution percentages for borrowing fees
    mapping(address => uint256) public totalFeesCollectedFromTrader; // tradefees total
    uint256 public lastUpdatedLpFeesCollected; // Last update timestamp
    uint256 public track24HoursLpFeesCollected; // Total LP fees collected in the current 24-hour window

    // ========================== Errors ========================== //

    error Keeper__UnauthorizedAccess();
    error Keeper__InvalidAddress();
    error Keeper__IncorrectTradeFeeDistribution();
    error Keeper__IncorrectBorrowFeeDistribution();
    error Keeper__UnauthorizedSequencer();

    // ========================== Events ========================== //
    event LpFeesCollected(uint256 lpEarning, uint256 timestamp);

    // ========================== Modifiers ========================== //

    modifier onlyDiamond() {
        require(msg.sender == diamond, Keeper__UnauthorizedAccess());
        _;
    }

    modifier onlySequencer() {
        bool isSequencerWhitelist = IViewFacet(diamond).isSequencerWhitelisted(msg.sender);
        require(isSequencerWhitelist, Keeper__UnauthorizedSequencer());
        _;
    }

    modifier onlyDiamondSequencer() {
        bool isSequencerWhitelist = IViewFacet(diamond).isSequencerWhitelisted(msg.sender);
        require(isSequencerWhitelist || msg.sender == diamond, Keeper__UnauthorizedSequencer());
        _;
    }

    // ========================== Functions ========================== //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() payable {
        _disableInitializers();
    }

    // ========================== External Functions ========================== //

    /**
     * @notice Pauses certain functions in the contract.
     */
    function pause() external payable onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses functions in the contract.
     */
    function unpause() external payable onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the address of the diamond contract.
     * @param _diamondContract Address of the diamond contract.
     */
    function setDiamondContract(address _diamondContract) external payable onlyOwner {
        require(_diamondContract != address(0), Keeper__InvalidAddress());
        if (diamond != _diamondContract) {
            diamond = _diamondContract;
            emit VaultContractUpdated(_diamondContract);
        }
    }

    /**
     * @notice Sets the address of the protocol treasury.
     * @param _protocolTreasury Address of the protocol treasury.
     */
    function setProtocolTreasury(address _protocolTreasury) external payable onlyOwner {
        require(_protocolTreasury != address(0), Keeper__InvalidAddress());
        if (protocolTreasury != _protocolTreasury) {
            protocolTreasury = _protocolTreasury;
            emit ProtocolTreasuryUpdated(_protocolTreasury);
        }
    }

    /**
     * @notice Sets the address of the insurance treasury.
     * @param _insurance Address of the insurance treasury.
     */
    function setInsuranceContract(address _insurance) external payable onlyOwner {
        require(_insurance != address(0), Keeper__InvalidAddress());
        if (insurance != _insurance) {
            insurance = _insurance;
            emit InsuranceUpdated(_insurance);
        }
    }

    /**
     * @notice Updates the trading fee distribution percentages.
     * @param _distribution Structure containing trading fee distribution percentages.
     */
    function updateTradingFeeDistribution(TradeFeeDistribution calldata _distribution) external payable onlyOwner {
        // IMP
        bool isValid = validateTradeFeeDistribution(_distribution);
        require(isValid, Keeper__IncorrectTradeFeeDistribution());
        tradeFeeDistribution = _distribution;
        emit TradingFeeDistributionUpdated(
            _distribution.referralPortion,
            _distribution.lp,
            _distribution.protocolTreasury,
            _distribution.filamentTokenStakers,
            _distribution.insurance
        );
    }

    /**
     * @notice Updates the borrowing fee distribution percentages.
     * @param _distribution Structure containing borrowing fee distribution percentages.
     */
    function updateBorrowingFeeDistribution(
        BorrowingFeeDistribution calldata _distribution // IMP
    ) external payable onlyOwner {
        bool isValid = validateBorrowFeeDistribution(_distribution);
        require(isValid, Keeper__IncorrectBorrowFeeDistribution());
        borrowingFeeDistribution = _distribution;
        emit BorrowingFeeDistributionUpdated(_distribution.lp, _distribution.protocolTreasury);
    }

    /**
     * @notice Distributes borrowing fees between the protocol treasury and liquidity providers (LP).
     * @dev Handles the transfer and distribution of borrowing fees.
     * @param feesInUSD The borrowing fees in USD (with 10^6 decimals).
     * @param _indexToken The address of the index token.
     */
    function distributeBorrowingFees(address _indexToken, uint256 feesInUSD) external onlyDiamond nonReentrant {
        // IMP
        address _usdc = address(usdc);
        address keeperAddr = address(this);
        grandTotalFeesCollected = grandTotalFeesCollected + feesInUSD;
        uint256 dnFeeInUSD = feesInUSD / 10 ** 12;
        // ITradeFacet(diamond).approveUSDC(dnFeeInUSD);
        uint256 prvBalance = IERC20(_usdc).balanceOf(keeperAddr);
        IERC20(_usdc).safeTransferFrom(diamond, keeperAddr, dnFeeInUSD);
        uint256 postBalance = IERC20(_usdc).balanceOf(keeperAddr);
        feesInUSD = (postBalance - prvBalance) * 10 ** 12;
        // 1. protocolTreasury, 20%
        uint256 treasuryPortion = (feesInUSD * borrowingFeeDistribution.protocolTreasury) / 10_000;
        uint256 dnTreasuryPortion = treasuryPortion / 10 ** 12;
        IERC20(_usdc).safeTransfer(protocolTreasury, dnTreasuryPortion);

        // 2. lp, 80%
        uint256 lpEarning = feesInUSD - treasuryPortion;
        uint256 dnLpEarning = lpEarning / 10 ** 12;
        IERC20(_usdc).approve(diamond, dnLpEarning);
        ITradeFacet(diamond).addLPFees(lpEarning, _indexToken);
        totalLpFeesCollected = totalLpFeesCollected + lpEarning;
        _update24HoursLpFeesCollected(lpEarning);
        emit LpFeesCollected(lpEarning, block.timestamp);
        // 70% of 80% (lp fees) will go to FLP Stakers
        // totalLpFeesForFLPStakers = totalLpFeesForFLPStakers + (7000 * lpEarning) / 1e4;
    }

    /**
     * @notice Distributes trade fees based on the trader type.
     * @dev Handles the distribution of trade fees among makers, takers, referral earnings, protocol treasury, and LP
     * fees.
     * @param feesInUSD The trade fees in USD (with 10^6 decimals).
     * @param _indexToken The address of the index token.
     * @param _account The address of the account associated with the trade.
     */
    function distributeTradeFees(uint256 feesInUSD, address _indexToken, address _account)
        // bool isFullyRebated // IMP
        external
        onlyDiamond
        whenNotPaused
        nonReentrant
    {
        // @note - No need for makerFeeRebateEarning separately
        // userFeeInfo[_account].makerFeeRebateEarning = userFeeInfo[_account].makerFeeRebateEarning + feesInUSD;
        _distributeTradeFees(feesInUSD, _indexToken, _account);
    }

    /**
     * @notice Collect the liquidation fees.
     * @param feesInUSD The trade fees in USD (with 10^18 decimals).
     */
    function updateLiquidationFeesCollected(uint256 feesInUSD) external onlyDiamond whenNotPaused nonReentrant {
        // IMP
        totalLiquidationFeesCollected = totalLiquidationFeesCollected + feesInUSD;
        grandTotalFeesCollected = grandTotalFeesCollected + feesInUSD;
    }

    // ========================== Public Functions ========================== //

    /**
     * @notice Initializes the contract with necessary parameters.
     * @param _usdc Address of the USDC token contract.
     * @param _protocolTreasury Address of the protocol treasury.
     * @param _insurance Address of the insurance contract.
     */
    function initialize(address _usdc, address _protocolTreasury, address _insurance) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        require(_usdc != address(0), Keeper__InvalidAddress());
        require(_protocolTreasury != address(0), Keeper__InvalidAddress());
        require(_insurance != address(0), Keeper__InvalidAddress());

        usdc = _usdc;
        protocolTreasury = _protocolTreasury;
        insurance = _insurance;
    }

    // ========================== Internal Functions ========================== //

    /**
     * @dev Ensures only the contract owner can authorize an upgrade.
     * @param newImplementation Address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    // ========================== Private Functions ========================== //

    // ========================== Pure & View Functions ========================== //

    /**
     * @notice Retrieves the total fees collected from a trader.
     * @param _account The address of the trader.
     * @return The total fees collected from the trader.
     */
    function getTotalFeesCollectedFromTrader(address _account) external view returns (uint256) {
        return totalFeesCollectedFromTrader[_account];
    }

    /**
     * @notice Retrieves the total LP fees collected.
     * @return The total LP fees collected.
     */
    function getTotalLpFeesCollected() external view returns (uint256) {
        return totalLpFeesCollected;
    }

    /**
     * @notice Retrieves the grand total fees collected (trade, borrow, and liquidation).
     * @return The grand total fees collected.
     */
    function getGrandTotalFeesCollected() external view returns (uint256) {
        return grandTotalFeesCollected;
    }

    /**
     * @notice Validates the borrowing fee distribution percentages.
     * @param _distribution Structure containing borrowing fee distribution percentages.
     * @return isValid True if the distribution is valid, false otherwise.
     */
    function validateBorrowFeeDistribution(BorrowingFeeDistribution calldata _distribution)
        public
        pure
        returns (bool isValid)
    {
        uint256 total = _distribution.lp + _distribution.protocolTreasury;
        return total == 10_000;
    }

    /**
     * @notice Validates the trading fee distribution percentages.
     * @param _distribution Structure containing trading fee distribution percentages.
     * @return isValid True if the distribution is valid, false otherwise.
     */
    function validateTradeFeeDistribution(TradeFeeDistribution calldata _distribution)
        public
        pure
        returns (bool isValid)
    {
        uint256 total = _distribution.referralPortion + _distribution.lp + _distribution.protocolTreasury
            + _distribution.filamentTokenStakers + _distribution.insurance;
        return total == 10_000;
    }

    /**
     * @notice Retrieves the address of the protocol treasury.
     * @return The address of the protocol treasury.
     */
    function getProtocolTreasury() external view returns (address) {
        return protocolTreasury;
    }

    /**
     * @notice Retrieves the address of the insurance contract.
     * @return The address of the insurance contract.
     */
    function getInsurance() external view returns (address) {
        return insurance;
    }

    /**
     * @notice Retrieves the LP fees collected in the last 24 hours.
     * @return fees LP fees collected in the last 24 hours.
     */
    function getLpFeesCollectedInLast24hours() external view returns (uint256 fees) {
        return track24HoursLpFeesCollected;
    }

    // ========================== Internal Functions ========================== //

    /**
     * @dev Internal function to distribute trade fees.
     * @param feesInUSD The trade fees in USD.
     * @param _indexToken The address of the index token.
     * @param _account The address of the account associated with the trade.
     */
    function _distributeTradeFees( // @note - huge scope for improvement after referral is moved to backend // IMP
    uint256 feesInUSD, address _indexToken, address _account)
        internal
    {
        address _usdc = usdc;
        address keeperAddr = address(this);
        // userFeeInfo[_account].totalFeesCollectedFromTrader =
        //     userFeeInfo[_account].totalFeesCollectedFromTrader + feesInUSD;
        totalFeesCollectedFromTrader[_account] += feesInUSD;
        grandTotalFeesCollected = grandTotalFeesCollected + feesInUSD;
        uint256 denormalizedFee = feesInUSD / 10 ** 12;
        uint256 prvBalance = IERC20(_usdc).balanceOf(keeperAddr);
        IERC20(_usdc).safeTransferFrom(msg.sender, keeperAddr, denormalizedFee);
        uint256 postBalance = IERC20(_usdc).balanceOf(keeperAddr);
        feesInUSD = (postBalance - prvBalance) * 10 ** 12;
        // 2. Distribute the referral Earning, 0%
        uint256 referralEarning;
        // 3. Distribute the protocol treasury, 35%
        uint256 treasuryPortion = (feesInUSD * tradeFeeDistribution.protocolTreasury) / 10_000;
        uint256 dnTreasuryPortion = treasuryPortion / 10 ** 12;
        IERC20(_usdc).safeTransfer(protocolTreasury, dnTreasuryPortion);
        uint256 insurancePortion;
        if (tradeFeeDistribution.insurance != 0) {
            // 4. Distribute the insurance, 20%
            insurancePortion = (feesInUSD * tradeFeeDistribution.insurance) / 10_000;
            uint256 dnInsurancePortion = insurancePortion / 10 ** 12;
            IERC20(_usdc).safeTransfer(insurance, dnInsurancePortion);
        }

        // 5. Distribute the Filament Token Staker fees, 0%
        uint256 filamentTokenStakerFees;
        if (tradeFeeDistribution.filamentTokenStakers != 0) {
            filamentTokenStakerFees = (feesInUSD * tradeFeeDistribution.filamentTokenStakers) / 10_000;
            // uint256 dnfilamentTokenStakerFees = filamentTokenStakerFees / 10 ** 12;
            // @note - In the future if stakerPortion needs to be added, we can add logic here.
        }

        // 6. Distribute the LP fees, 45%
        uint256 lpEarning = feesInUSD - referralEarning - treasuryPortion - filamentTokenStakerFees - insurancePortion;
        uint256 dnLpEarning = lpEarning / 10 ** 12;
        IERC20(_usdc).approve(diamond, dnLpEarning);
        ITradeFacet(diamond).addLPFees(lpEarning, _indexToken);
        totalLpFeesCollected = totalLpFeesCollected + lpEarning;
        _update24HoursLpFeesCollected(lpEarning);
        emit LpFeesCollected(lpEarning, block.timestamp);
    }

    /**
     * @dev Internal function to handle LP fee update logic.
     * @param lpEarning The LP earnings to update.
     */
    function _update24HoursLpFeesCollected(uint256 lpEarning) internal {
        // IMP
        uint256 timeSinceLastUpdate = block.timestamp - lastUpdatedLpFeesCollected;

        if (timeSinceLastUpdate >= 24 hours) {
            // Reset the tracked fees for the new 24-hour window
            track24HoursLpFeesCollected = lpEarning;
            lastUpdatedLpFeesCollected = block.timestamp; // Update only in this block
        } else {
            // Add to the currently tracked LP fees
            track24HoursLpFeesCollected += lpEarning;
        }
    }

}
