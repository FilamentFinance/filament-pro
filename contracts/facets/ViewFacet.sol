// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import {
    BorrowedAmount,
    Compartment,
    INTEREST_RATE_DECIMALS,
    InterestRateParameters,
    Position,
    Stake,
    UnstakeRequest
} from "../interfaces/ICommon.sol";

import { AppStorage } from "../AppStorage.sol";
import { IKeeper } from "../interfaces/IKeeper.sol";
import { IViewFacet } from "../interfaces/IViewFacet.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ViewFacet
/// @author Filament
/// @notice Facet contract providing view functions for various storage variables in the protocol
/// @dev This contract provides read-only access to protocol data stored in the AppStorage contract
contract ViewFacet is IViewFacet {

    AppStorage internal s;

    // ========================== Functions ========================== //

    // ========================== View and Pure Functions ========================== //

    /// @notice Checks if a specific sequencer is whitelisted in the protocol
    /// @param _sequencer The address of the sequencer
    /// @return A boolean value indicating whether the sequencer is whitelisted
    function isSequencerWhitelisted(address _sequencer) public view returns (bool) {
        return s.isSequencer[_sequencer];
    }

    /// @notice Retrieves the last liquidation leverage update time set for a specific token
    /// @param token The address of the token
    /// @return The last liquidation leverage set time for the token
    function getLastLiquidationLeverageUpdateTime(address token) public view returns (uint256) {
        return s.lastLiquidationLeverageUpdate[token];
    }

    /// @notice Retrieves the Liquidation Leverage for a specific token
    /// @param token The address of the token
    /// @return The Liquidation Leverage for the token
    function getLiquidationLeverage(address token) public view returns (uint256) {
        return s.liquidationLeverage[token];
    }

    /// @notice Retrieves the ADL percentage set for a specific token
    /// @param token The address of the token
    /// @return The ADL percentage for the token
    function getADLpercentage(address token) public view returns (uint256) {
        return s.adlPercentage[token];
    }

    /// @notice Retrieves the epoch duration configured in the protocol
    /// @return The duration of each epoch
    function epochDuration() public view returns (uint256) {
        return s.epochDuration;
    }

    /// @notice Retrieves the default compartmentalization time configured in the protocol
    /// @return The default compartmentalization time
    function compartmentalizationTime() public view returns (uint256) {
        return s.compartmentalizationTime;
    }

    /// @notice Retrieves the last traded price of a specific index token
    /// @param indexToken The address of the index token
    /// @return The last traded price of the index token
    function getLastTradedPrice(address indexToken) public view returns (uint256) {
        return s.lastTradedPrice[indexToken];
    }

    /// @notice Retrieves the compartment details for a specific index token
    /// @param _indexToken The address of the index token
    /// @return balance The balance of the compartment
    /// @return assignedPercentage The assigned percentage of the compartment
    /// @return isValid Whether the compartment is valid or not
    function compartments(address _indexToken)
        public
        view
        returns (uint256 balance, uint256 assignedPercentage, bool isValid)
    {
        Compartment memory comp = s.compartments[_indexToken];
        return (comp.balance, comp.assignedPercentage, comp.isValid);
    }

    /// @notice Retrieves the borrowed amount from the pool for a specific index token
    /// @param _indexToken The address of the index token
    /// @return total The total borrowed amount from the pool
    /// @return long The amount borrowed in long positions
    /// @return short The amount borrowed in short positions
    function borrowedAmountFromPool(address _indexToken)
        public
        view
        returns (uint256 total, uint256 long, uint256 short)
    {
        BorrowedAmount memory amt = s.borrowedAmountFromPool[_indexToken];
        return (amt.total, amt.long, amt.short);
    }

    /// @notice Retrieves the compartments borrowing details for a specific index token
    /// @param _indexToken The address of the index token
    /// @return availBalance The balance of the compartment
    /// @return totalBorrowed The total borrowed amount from the pool
    function compartmentBorrowDetails(address _indexToken)
        public
        view
        returns (uint256 availBalance, uint256 totalBorrowed)
    {
        Compartment memory comp = s.compartments[_indexToken];
        BorrowedAmount memory amt = s.borrowedAmountFromPool[_indexToken];
        return (comp.balance, amt.total);
    }

    /// @notice Retrieves the address of the index token at a specific index in the allIndexTokens array
    /// @param ind The index of the token in the allIndexTokens array
    /// @return The address of the index token
    function allIndexTokens(uint256 ind) public view returns (address) {
        return s.allIndexTokens[ind];
    }

    /// @notice Retrieves the total order book traded size for a specific index token
    /// @param indexToken The address of the index token
    /// @return The total order book traded size of the index token
    function getTotalOBTradedSize(address indexToken) public view returns (uint256) {
        return s.totalOBTradedSize[indexToken];
    }

    /// @notice Retrieves the total number of index tokens registered in the protocol
    /// @return The total number of index tokens
    function getTotalIndexTokens() public view returns (uint256) {
        return s.allIndexTokens.length;
    }

    /// @notice Retrieves the minimum dust size set in the protocol
    /// @return The dust size
    function getDustSize() public view returns (uint256) {
        return s.dustSize;
    }

    /// @notice Retrieves the collateral in long positions of a specific index token
    /// @param indexToken The address of the index token
    /// @return The collateral in long positions for the index token
    function getLongCollateral(address indexToken) public view returns (uint256) {
        return s.longCollateral[indexToken];
    }

    /// @notice Retrieves the collateral in short positions of a specific index token
    /// @param indexToken The address of the index token
    /// @return The collateral in short positions for the index token
    function getShortCollateral(address indexToken) public view returns (uint256) {
        return s.shortCollateral[indexToken];
    }

    /// @notice Retrieves the current USD balance of the protocol
    /// @return The current USD balance
    function getUsdBalance() public view returns (uint256) {
        return s.usdBalance;
    }

    /// @notice Retrieves the total borrowed amount in USD from the protocol
    /// @return The total borrowed amount in USD
    function totalBorrowedUSD() public view returns (uint256) {
        return s.totalBorrowedUSD;
    }

    /// @notice Checks if a given token address is registered as an index token in the protocol
    /// @param _indexToken The address of the index token
    /// @return Whether the token is registered as an index token (true) or not (false)
    function isValidIndexToken(address _indexToken) public view returns (bool) {
        return s.isIndexToken[_indexToken];
    }

    /// @notice Retrieves the maximum leverage a liquidator can use to acquire a position
    /// @return The maximum liquidator leverage
    function getMaxLiquidatorLeverageToAcquirePosition() public view returns (uint256) {
        return s.maxLiquidatorLeverageToAcquirePosition;
    }

    /// @notice Generates a unique key for a position based on trader's account, index token, and position type
    /// @param _account The address of the trader's account
    /// @param _previousAccount The address of the previous account (can be zero)
    /// @param _indexToken The address of the index token
    /// @param _isLong Whether the position is long (true) or short (false)
    /// @return A bytes32 unique key representing the position
    function getPositionKey(address _account, address _previousAccount, address _indexToken, bool _isLong)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_account, _previousAccount, _indexToken, _isLong));
    }

    /// @notice Retrieves the details of a position using its unique key
    /// @param key The unique key representing the position
    /// @return The position struct
    function getPosition(bytes32 key) public view returns (Position memory) {
        return s.positions[key];
    }

    /// @notice Retrieves the size of a position based on account, index token, and position type
    /// @param _account The address of the trader's account
    /// @param _indexToken The address of the index token
    /// @param _isLong Whether the position is long (true) or short (false)
    /// @return The size of the position
    function getPositionSize(address _account, address _indexToken, bool _isLong) public view returns (uint256) {
        bytes32 key = getPositionKey(_account, address(0), _indexToken, _isLong);

        Position memory position = getPosition(key);
        return position.size;
    }

    /// @notice Returns the optimal utilization for a given index token
    /// @dev This function fetches the optimal utilization value from the state mapping `optimalUtilization`
    /// @param _indexToken The address of the index token for which the optimal utilization is being fetched
    /// @return The optimal utilization value for the given index token as a `uint256`
    function getOptimalUtilization(address _indexToken) public view returns (uint256) {
        return s.optimalUtilization[_indexToken];
    }

    /// @notice Retrieves the router contract address used by the protocol
    /// @return The address of the router contract
    function getRouterContract() public view returns (address) {
        return s.router;
    }

    /// @notice Retrieves the LP token contract address
    /// @return The address of the LP token contract
    function getLPTokenAddress() public view returns (address) {
        return s.lpToken;
    }

    /// @notice Retrieves the deposit contract address used by the protocol
    /// @return The address of the deposit contract
    function getDepositContract() public view returns (address) {
        return s.deposit;
    }

    /// @notice Retrieves the USDC contract address used in the protocol
    /// @return The address of the USDC contract
    function getUSDCContract() public view returns (address) {
        return s.usdc;
    }

    /// @notice Retrieves the escrow contract address
    /// @return The address of the escrow contract
    function getEscrowContract() public view returns (address) {
        return s.escrow;
    }

    /// @notice Retrieves the protocol liquidator address
    /// @return The address of the protocol liquidator
    function isProtocolLiquidatorAddress(address _address) public view returns (bool) {
        return s.isProtocolLiquidator[_address];
    }

    /// @notice Retrieves the keeper contract address used for protocol maintenance
    /// @return The address of the keeper contract
    function getKeeperContract() public view returns (address) {
        return s.keeper;
    }

    /// @notice Retrieves the stake details of a specific account
    /// @param _account The address of the account
    /// @return stakedAmount The amount staked by the account
    /// @return unstakedRequested The amount requested to unstake by the account
    /// @return unclaimAmount The amount unclaimed by the account
    function stakes(address _account) public view returns (uint256, uint256, uint256) {
        Stake memory st = s.stakes[_account];
        return (st.stakedAmount, st.unstakedRequested, st.unstakeClaimed);
    }

    /// @notice Calculates the claimable amount for unstaking by a specific account
    /// @param _address The address of the account
    /// @return claimableAmount The amount claimable by the account
    function getClaimableAmount(address _address) public view returns (uint256 claimableAmount) {
        // #Zokyo-52
        UnstakeRequest[] memory unstakeRequests = s.unstakeRequests[_address];
        Stake memory st = s.stakes[_address];

        claimableAmount = st.unstakedRequested - st.unstakeClaimed; // all 18 decimals
        uint256 today = block.timestamp;

        // This loop will run a maximum of 7 iterations,
        // as the requests are sorted and the loop will break
        // and the remaining will have been matured
        if (unstakeRequests.length == 0) {
            return 0;
        }
        uint256 len = unstakeRequests.length;
        for (uint256 i = len; i > 0; --i) {
            if (today - unstakeRequests[i - 1].requestDay >= 7 days) {
                break;
            } else {
                claimableAmount = claimableAmount
                    - (unstakeRequests[i - 1].amount * (7 - (today - unstakeRequests[i - 1].requestDay) / 86_400)) / 7;
            }
        }
    }

    /// @notice Gets the total amount of FLP tokens staked in the protocol
    /// @return totalFLPStaked The total amount of FLP tokens staked
    function getTotalFLPStaked() public view returns (uint256 totalFLPStaked) {
        return s.totalFLPStaked;
    }

    /// @notice Retrieves the unstake requests made by a specific staker
    /// @param staker The address of the staker
    /// @return The array of unstake requests made by the staker
    function requests(address staker) public view returns (UnstakeRequest[] memory) {
        return s.unstakeRequests[staker];
    }

    /// @notice Retrieves the interest rate parameters for a specific index token
    /// @param indexToken The address of the index token
    /// @return The interest rate parameters struct for the given index token
    function getInterestRateParams(address indexToken) public view returns (InterestRateParameters memory) {
        return s.interestRateParameters[indexToken];
    }

}
