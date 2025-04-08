// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import {
    BorrowedAmount,
    Compartment,
    InterestRateParameters,
    Position,
    Stake,
    UnstakeRequest
} from "./interfaces/ICommon.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

struct AppStorage {
    /// @notice Dust Size
    /// @dev $0.0001
    uint256 dustSize;
    /// @dev state variables keep track of the USD balance within the vault
    uint256 usdBalance;
    /// @notice The total USD amount that's locked and can't be withdrawn.
    uint256 totalBorrowedUSD;
    /// @notice Total duration of complete rebalancing in hours
    uint256 epochDuration;
    /// @notice Frequency of compartmentalization in seconds
    uint256 compartmentalizationTime;
    /// @notice Last blockTime of compartmentalization
    uint256 lastCompartmentalizationTime;
    /// @notice Total duration of since last rebalancing in hours
    uint256 epochInterval;
    uint256 totalFLPStaked;
    uint256 maxLiquidatorLeverageToAcquirePosition;
    uint256 combPoolLimit;
    uint256 maxLeverage;
    /// @notice The address of the router contract.
    address router;
    /// @notice Stores the contract addresses for LP token
    address lpToken;
    /// @notice Stores the contract addresses for deposit contract
    address deposit;
    /// @notice Stores the contract addresses for the USDC token
    address usdc;
    /// @notice Escrow contract
    address escrow;
    /// @notice The keeper contract address
    address keeper;
    /// @notice This array keeps track of all the index tokens that are recognized by the vault.
    address[] allIndexTokens;
    /// @notice Compartment with less amount than it should have
    address[] invalidAssets;
    /// @notice Compartment with more or equal amount that it should have
    address[] validAssets;
    /// @notice These are the amounts on which borrowingRate is paid
    mapping(address => BorrowedAmount) borrowedAmountFromPool;
    /// @notice This is the position on which fundingRate are paid
    /// @dev Note that the long and short amount will be exactly equal, in each asset and hence at protocol level too
    mapping(address => uint256) totalOBTradedSize;
    /// @notice Tracks the total collateral locked in long positions for each token.
    mapping(address => uint256) longCollateral;
    /// @notice Tracks the total collateral locked in short positions for each token.
    mapping(address => uint256) shortCollateral;
    /// @notice Percentage at which ADL will hit, might be different for different tokens
    mapping(address => uint256) adlPercentage;
    /// @notice Desired utilization
    mapping(address => uint256) optimalUtilization;
    mapping(address => uint256) lastTradedPrice;
    /// @notice Amount of last transfer usdc form any compartment or to any compartment while compartmentalization
    mapping(address => uint256) lastTransferUSDC;
    /// @notice Mappings to track extra USD balance required after last compartmentalization
    mapping(address => uint256) lastRequirement;
    /// @notice Mappings to track extra USD balance available after last compartmentalization
    mapping(address => uint256) lastAvailable;
    /// @notice Last liquidationLeverage updated time
    mapping(address => uint256) lastLiquidationLeverageUpdate;
    /// @notice New liquidationLeverage used in liquidation
    mapping(address => uint256) liquidationLeverage;
    /// @notice If the given address is index token reverts true
    mapping(address => bool) isIndexToken;
    mapping(address => bool) isProtocolLiquidator;
    /// @notice A mapping to keep track of whether Automatic Deleveraging (ADL) is active for a particular address
    /// (token).
    mapping(address => Compartment) compartments;
    /// @notice A mapping that relates an address to its Stake struct, keeping track of all stakes in the contract.
    mapping(address => Stake) stakes;
    /// @notice A mapping that relates an address to its Unstake struct, keeping track of all unstakes requests.
    mapping(address => UnstakeRequest[]) unstakeRequests;
    mapping(address => bool) isSequencer;
    mapping(address => InterestRateParameters) interestRateParameters;
    /// @notice Stores the positions of traders. Each position is identified by a unique key (bytes32) which is a
    /// @dev hash of the trader's account, index token, and the position type (long or short).
    mapping(bytes32 => Position) positions;
}
