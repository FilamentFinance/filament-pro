// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { AppStorage } from "../AppStorage.sol";
import {
    BASIS_POINTS_DIVISOR, Compartment, INTEREST_RATE_DECIMALS, Position, TraderType
} from "../interfaces/ICommon.sol";
import { IDeposit } from "../interfaces/IDeposit.sol";
import { IEscrow } from "../interfaces/IEscrow.sol";
import { IKeeper } from "../interfaces/IKeeper.sol";
import { IRouter } from "../interfaces/IRouter.sol";
import { ITradeFacet } from "../interfaces/ITradeFacet.sol";
import { IVaultFacet } from "../interfaces/IVaultFacet.sol";
import { IViewFacet } from "../interfaces/IViewFacet.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "hardhat/console.sol";
/**
 * @title Trade Contract
 * @author Filament Finance
 * @notice This contract handles position management including creation, modification and liquidation
 * @dev Implements core trading functionality for the protocol including:
 * - Position creation and increase
 * - Position decrease and closing
 * - Liquidation handling
 * - Fee calculation and collection
 * - Collateral management
 */

contract TradeFacet is ITradeFacet, PausableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    AppStorage internal s;

    // ========================== Errors ========================== //

    error TradeFacet__OnlyKeeper();
    error TradeFacet__OnlyRouterSequencer();
    error TradeFacet__OnlyProtocolLiquidator();
    error TradeFacet__PositionNotExist();
    error TradeFacet__PositionNotLiquidable();
    error TradeFacet__PositionShouldHaveLiquidated();
    error TradeFacet__InvalidAsset();
    error TradeFacet__FeeLargerThanCollateral();
    error TradeFacet__NonZeroPositionSizeNeeded();
    error TradeFacet__IndexDeltaMoreThanMaxUsdc();
    error TradeFacet__IndexDeltaMoreThanSize();
    error TradeFacet__DeltaLessThanCollateral();
    error TradeFacet__AvgPriceIsZero();
    error TradeFacet__MaxIntValueExceeded();
    error TradeFacet__ExceedsMaxAllowedLeverage();
    error TradeFacet__LowCollateral();
    error TradeFacet__FundingFeeMismatch();
    error TradeFacet__LengthMismatch();
    error TradeFacet__IncorrectFeeCondition();
    error TradeFacet__IncorrectBorrowFee();
    error TradeFacet__LossMoreThanPositionCollateral();
    error IncreasePosition_IncorrectBorrowAndFundingFee();
    error TradeFacet__TradeFeeLargerThanCollateralDelta();

    // ========================== Events ========================== //

    /// @notice Emitted when profit is realized
    event Profit(address indexToken, uint256 profit, bool hasprofit);
    /// @notice Emitted when ADL is triggered for a position
    event ADLTriggered(
        address account,
        address indexToken,
        bool isLong,
        uint256 size,
        uint256 viaOB,
        uint256 reserveAmount,
        uint256 collateral,
        uint256 price,
        uint256 tradeFee,
        uint256 borrowFee,
        int256 fundingFee
    );
    /// @notice Emitted when total borrowed amount is updated
    event TotalBorrowedUpdated(uint256 newTotalBorrowed);
    /// @notice Emitted when LP fees are added
    event LPFeesAdded(uint256 feesUSD, address indexToken);
    /// @notice Emitted when compartment balance is reduced
    event CompartmentBalanceReduced(address asset, uint256 amount);
    /// @notice Emitted when compartment balance is increased
    event CompartmentBalanceIncreased(address asset, uint256 amount);
    /// @notice Emitted when profit is transferred out
    event TransferOutProfit(address token, uint256 amount, address receiver);
    /// @notice Emitted when total trading fees are calculated
    event TotalTradingFees(
        address account,
        TraderType traderType,
        int256 totalFees,
        uint256 tradeFees,
        uint256 borrowFees,
        int256 fundingFee,
        uint256 timestamp
    );
    /// @notice Emitted when a position is increased
    event IncreasePosition(
        bytes32 key,
        address account,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        int256 fee,
        bool isPositionIncreased,
        uint256 orderId
    );
    /// @notice Emitted when a position is updated
    event UpdatePosition(
        bytes32 key,
        uint256 size,
        address indexToken,
        uint256 collateral,
        uint256 averagePrice,
        uint256 reserveAmount,
        uint256 viaOrderBook,
        int256 realisedPnl,
        uint256 markPrice,
        uint256 orderId,
        address account,
        uint256 creationTimestamp
    );
    /// @notice Emitted when a position is decreased
    event DecreasePosition(
        bytes32 key,
        address account,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        int256 fee,
        bool isPositionIncreased,
        uint256 orderId,
        uint256 borrowFee,
        int256 fundingFee
    );
    /// @notice Emitted when a position is closed
    event ClosePosition(
        bytes32 key,
        uint256 size,
        address indexToken,
        uint256 collateral,
        uint256 averagePrice,
        uint256 reserveAmount,
        uint256 viaOrderBook,
        int256 realisedPnl,
        uint256 orderId
    );
    /// @notice Emitted when a position is liquidated
    event LiquidatePosition(
        bytes32 key, address account, address indexToken, bool isLong, uint256 size, uint256 collateral
    );
    /// @notice Emitted when a position is transferred
    event TransferPosition(
        bytes32 newKey,
        address fromAccount,
        address toAccount,
        address indexToken,
        bool isLong,
        uint256 newPositionSize,
        uint256 newPositionCollateral,
        uint256 averagePrice,
        uint256 reserveAmount,
        uint256 viaOrder,
        uint256 timestamp
    );
    /// @notice Emitted when realized PnL is calculated
    event CurrentRealisedPnL(
        bytes32 key,
        address account,
        address indexToken,
        uint256 indexDelta,
        bool isLong,
        int256 currentRealisedPnL,
        uint256 orderId
    );
    /// @notice Emitted when COMB pool balance is decreased
    event DecreaseCOMBPoolBalance(
        address indexToken,
        address account,
        TraderType traderType,
        uint256 amount,
        uint256 beforeCOMBPoolBalance,
        uint256 afterCOMBPoolBalance,
        uint256 beforeCompartmentBalance,
        uint256 afterCompartmentBalance,
        uint256 beforeTotalBorrowed,
        uint256 afterTotalBorrowed,
        uint256 timestamp
    );
    /// @notice Emitted when COMB pool balance is increased
    event IncreaseCOMBPoolBalance(
        address indexToken,
        address account,
        TraderType traderType,
        uint256 amount,
        uint256 beforeCOMBPoolBalance,
        uint256 afterCOMBPoolBalance,
        uint256 beforeCompartmentBalance,
        uint256 afterCompartmentBalance,
        uint256 beforeTotalBorrowed,
        uint256 afterTotalBorrowed,
        uint256 timestamp
    );
    event Log(string message);
    event LogInt(int256 intValue, int256 longValue, int256 shortValue);
    event LogUint(uint256 uintValue1, uint256 uintValue2, uint256 uintValue3);
    event NewPositionCreated(bytes32 key);

    // ========================== Modifiers ========================== //

    /// @notice Restricts function access to keeper only
    modifier onlyKeeper() {
        require(msg.sender == s.keeper, TradeFacet__OnlyKeeper());
        _;
    }

    /// @notice Restricts function access to router or sequencer only
    modifier onlyRouterSequencer() {
        require(msg.sender == s.router || s.isSequencer[msg.sender], TradeFacet__OnlyRouterSequencer());
        _;
    }

    /// @notice Restricts function access to protocol liquidator only
    modifier onlyProtocolLiquidator() {
        require(s.isProtocolLiquidator[msg.sender], TradeFacet__OnlyProtocolLiquidator());
        _;
    }

    // ========================== Functions ========================== //

    // ========================== External Functions ========================== //

    /// @notice Increases the position for a given account based on the provided parameters and price
    /// @dev This function performs several checks and updates related to the position, including
    ///      validating the index token, calculating the new average price, transferring collateral,
    ///      collecting fees, and updating the position's details. The function also ensures the position
    ///      is not liquidatable after the increase.
    /// @param _increasePositionParams The parameters for increasing the position
    /// @return The updated Position struct
    function increasePosition(PositionParams memory _increasePositionParams)
        external
        nonReentrant
        onlyRouterSequencer
        returns (Position memory)
    {
        return _increasePosition(_increasePositionParams);
    }

    /// @notice Decreases a position based on the provided parameters
    /// @dev Handles position size reduction, collateral withdrawal, and fee collection
    /// @param decreasePosition_ The parameters for decreasing the position
    /// @return The amount of collateral withdrawn
    function decreasePosition(PositionParams memory decreasePosition_)
        external
        nonReentrant
        onlyRouterSequencer
        returns (uint256)
    {
        return _decreasePosition(decreasePosition_);
    }

    /// @notice Transfers a position to an escrow contract for liquidation
    /// @dev Only callable by the protocol liquidator. This function validates that the position exists and is
    /// liquidatable,
    ///      then processes the liquidation by either decreasing a pool position or directly updating collateral values.
    ///      The position's collateral is reduced by liquidation fees and funding/borrow fees are settled.
    /// @param _account The address of the account holding the position to liquidate
    /// @param _indexToken The address of the index token for the position
    /// @param _isLong Whether the position is long (true) or short (false)
    /// @param _price The current oracle price of the index token
    /// @param _orderId The unique identifier for this liquidation order
    /// @param _borrowFee The accumulated borrow fee that needs to be settled
    /// @param _tradeFee The trading fee for liquidation (must be 0)
    /// @param _liquidationFee The fee charged for liquidation
    /// @param _fundingFee The accumulated funding fee that needs to be settled (can be positive or negative)
    /// @custom:throws TradeFacet__PositionNotExist If the position does not exist
    /// @custom:throws TradeFacet__PositionNotLiquidable If the position is not eligible for liquidation
    function transferPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _price,
        uint256 _orderId,
        uint256 _borrowFee,
        uint256 _tradeFee,
        uint256 _liquidationFee,
        int256 _fundingFee
    ) external nonReentrant onlyProtocolLiquidator {
        address _contractAddress = address(this);
        bytes32 key = IViewFacet(_contractAddress).getPositionKey(_account, address(0), _indexToken, _isLong);
        Position memory position = IViewFacet(_contractAddress).getPosition(key);
        require(position.size != 0, TradeFacet__PositionNotExist());
        (bool liquidable, int256 currentCollateral) =
            validateliquidation(key, _price, _fundingFee, _borrowFee, _liquidationFee);
        require(liquidable, TradeFacet__PositionNotLiquidable());
        bytes32 oldKey = key;
        // require(_borrowFee > 0 && _tradeFee == 0, TransferPosition_IncorrectFee());
        if (position.reserveAmount != 0) {
            // Pool position exists
            PositionParams memory decreasePosition_ = PositionParams({
                account: _account,
                indexToken: _indexToken,
                collateralDelta: 0,
                indexDelta: position.reserveAmount,
                isLong: _isLong,
                matchType: MatchType.MatchWithPool,
                traderType: TraderType.Taker,
                price: _price,
                orderId: _orderId,
                fundingFee: _fundingFee,
                borrowFee: _borrowFee,
                tradeFee: _tradeFee
            });
            emit Log("transferPosition1");
            position.collateral -= _liquidationFee;
            _decreasePosition(decreasePosition_);
        } else {
            // No pool position
            // @note - update the collateral, without calling decrease position
            emit Log("transferPosition2");
            position.collateral -= (_borrowFee + _liquidationFee);
            uint256 uFundingFee = convertToInt256ToUint256(_fundingFee);
            address indexToken = position.indexToken;
            if (position.isLong) {
                emit Log("transferPosition3");
                s.longCollateral[indexToken] -= (_borrowFee + _liquidationFee);
                if (_fundingFee > 0) {
                    s.shortCollateral[indexToken] -= uFundingFee;
                    s.longCollateral[indexToken] += uFundingFee;
                    position.collateral = position.collateral + uFundingFee;
                } else {
                    s.shortCollateral[indexToken] += uFundingFee;
                    s.longCollateral[indexToken] -= uFundingFee;
                    position.collateral = position.collateral - uFundingFee;
                }
            } else {
                emit Log("transferPosition4");
                s.shortCollateral[indexToken] -= (_borrowFee + _liquidationFee);
                if (_fundingFee > 0) {
                    s.longCollateral[indexToken] -= uFundingFee;
                    s.shortCollateral[indexToken] += uFundingFee;
                    position.collateral = position.collateral + uFundingFee;
                } else {
                    s.longCollateral[indexToken] += uFundingFee;
                    s.shortCollateral[indexToken] -= uFundingFee;
                    position.collateral = position.collateral - uFundingFee;
                }
            }

            s.positions[oldKey] = position;
        }

        address _protocolTreasury = IKeeper(s.keeper).getProtocolTreasury();
        uint256 prvBalance = IERC20(s.usdc).balanceOf(_contractAddress);
        IERC20(s.usdc).safeTransfer(_protocolTreasury, (_liquidationFee / (10 ** 12)));
        uint256 postBalance = IERC20(s.usdc).balanceOf(_contractAddress);
        IKeeper(s.keeper).updateLiquidationFeesCollected((prvBalance - postBalance) * 10 ** 12);

        bytes32 newKey = IViewFacet(_contractAddress).getPositionKey(s.escrow, _account, _indexToken, _isLong);
        Position memory oldPosition = IViewFacet(_contractAddress).getPosition(key);
        s.positions[newKey] = oldPosition;
        uint256 collateralNeeded = (oldPosition.size / s.maxLiquidatorLeverageToAcquirePosition);
        uint256 uCurrentCollateral = convertToInt256ToUint256(currentCollateral);
        // @audit - PVE006 - If it's negative, liquidator needs to add extra additional collateral along with existing
        // collateral to acquire the position.
        uint256 liquidatorCollateralNeeded;
        if (currentCollateral > 0) {
            liquidatorCollateralNeeded =
                collateralNeeded > uCurrentCollateral ? collateralNeeded - uCurrentCollateral : 0;
        } else {
            liquidatorCollateralNeeded = collateralNeeded + uCurrentCollateral;
        }
        IEscrow(s.escrow).updateAllLiquidablePositions(newKey, liquidatorCollateralNeeded, oldPosition);
        delete s.positions[oldKey];
        emit LiquidatePosition(oldKey, _account, _indexToken, _isLong, position.size, position.collateral);
        emit TransferPosition(
            newKey,
            _account,
            s.escrow,
            _indexToken,
            _isLong,
            oldPosition.size,
            oldPosition.collateral,
            oldPosition.averagePrice,
            oldPosition.reserveAmount,
            oldPosition.viaOrder,
            block.timestamp
        );
    }

    /// @notice Liquidates a position through Auto-Deleveraging (ADL) by matching with the pool
    /// @dev Can only be called by the protocol liquidator. Uses nonReentrant guard.
    /// @param _account The address of the trader whose position is being liquidated
    /// @param _indexToken The address of the index token for the position
    /// @param _isLong Whether the position is long (true) or short (false)
    /// @param _price The price at which to liquidate the position
    /// @param _fundingFee The funding fee amount (can be positive or negative)
    /// @param _matchId The ID of the match for this liquidation
    /// @param _borrowFee The borrowing fee amount to be charged
    /// @param _tradeFee The trading fee amount to be charged
    function liquidateMatchWithPoolADL(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _price,
        int256 _fundingFee,
        uint256 _matchId,
        uint256 _borrowFee,
        uint256 _tradeFee
    ) external nonReentrant onlyProtocolLiquidator {
        address _contractAddr = address(this);
        bytes32 key = IViewFacet(_contractAddr).getPositionKey(_account, address(0), _indexToken, _isLong);
        Position memory position = IViewFacet(_contractAddr).getPosition(key);
        require(position.size != 0, TradeFacet__PositionNotExist());
        // require(IVaultFacet(_contractAddr).isADLNeeded(_indexToken, _price), TradeFacet__ADLNotRequired());

        PositionParams memory decreasePosition_ = PositionParams({
            account: _account,
            indexToken: _indexToken,
            collateralDelta: 0,
            indexDelta: position.reserveAmount,
            isLong: _isLong,
            matchType: MatchType.MatchWithPool,
            traderType: TraderType.Taker,
            price: _price,
            orderId: _matchId,
            fundingFee: _fundingFee,
            borrowFee: _borrowFee,
            tradeFee: _tradeFee
        });

        _decreasePosition(decreasePosition_);
        emit ADLTriggered(
            _account,
            _indexToken,
            _isLong,
            position.size,
            position.viaOrder,
            position.reserveAmount,
            position.collateral,
            _price,
            _tradeFee,
            _borrowFee,
            _fundingFee
        );
    }

    /// @notice Distributes hourly fees including both borrow and funding fees
    /// @param indexToken The token to distribute fees for
    /// @param borrowFee The borrow fee amount to distribute
    /// @param keys Array of position keys to distribute funding fees to
    /// @param fundFeeValues Array of funding fee values corresponding to the keys
    function hourlyFeeDistribution(
        address indexToken,
        uint256 borrowFee,
        bytes32[] memory keys,
        int256[] memory fundFeeValues
    ) external onlyRouterSequencer {
        _borrowFeeDistribution(indexToken, borrowFee);
        _fundingFeeDistribution(indexToken, keys, fundFeeValues);
    }

    /// @notice Distributes borrow fees for a token
    /// @param indexToken The token to distribute borrow fees for
    /// @param borrowFee The borrow fee amount to distribute
    function borrowFeeDistribution(address indexToken, uint256 borrowFee) external onlyRouterSequencer {
        _borrowFeeDistribution(indexToken, borrowFee);
    }

    /// @notice Distributes funding fees for positions
    /// @param indexToken The token to distribute funding fees for
    /// @param keys Array of position keys to distribute to
    /// @param fundFeeValues Array of funding fee values for each position
    function fundingFeeDistribution(address indexToken, bytes32[] memory keys, int256[] memory fundFeeValues)
        external
        onlyRouterSequencer
    {
        _fundingFeeDistribution(indexToken, keys, fundFeeValues);
    }

    // ========================== Public Functions ========================== //
    /// @notice Calculates the current collateral value of a position after accounting for PnL and fees
    /// @dev Retrieves position details and calculates:
    ///      1. Position's profit/loss based on entry and current price
    ///      2. Applies funding, borrowing and liquidation fees
    ///      3. Returns negative value if losses exceed collateral (only for protocol liquidator)
    /// @param key The unique identifier of the position
    /// @param _price The current price of the index token
    /// @param _fundingFee The funding fee amount (positive means trader receives, negative means trader pays)
    /// @param _borrowFee The borrowing fee amount charged to the trader
    /// @param _liquidationFee The liquidation fee amount charged during liquidation
    /// @return availabeCollateral The current collateral value after applying all fees and PnL
    function getCurrentCollateral(
        bytes32 key,
        uint256 _price,
        int256 _fundingFee,
        uint256 _borrowFee,
        uint256 _liquidationFee
    ) public view returns (int256 availabeCollateral) {
        address _contractAddr = address(this);
        Position memory position = IViewFacet(_contractAddr).getPosition(key);

        int256 pnl;

        (bool _isProfit, uint256 delta) = getDelta(position.size, position.averagePrice, position.isLong, _price);

        pnl = _isProfit ? int256(delta) : toNegativeInt256(delta);

        int256 pnlWithFees = pnl - int256(_borrowFee) - int256(_liquidationFee) + _fundingFee;
        if (pnlWithFees > 0) {
            return int256(position.collateral);
        } else {
            uint256 posPnlWithFees = convertToInt256ToUint256(pnlWithFees);

            if (posPnlWithFees >= position.collateral) {
                if (s.isProtocolLiquidator[msg.sender]) {
                    // negative scenarios should be considerred
                    availabeCollateral = int256(position.collateral) - int256(posPnlWithFees);
                    return availabeCollateral;
                } else {
                    revert TradeFacet__PositionShouldHaveLiquidated();
                }
            } else {
                availabeCollateral = int256(position.collateral) - int256(posPnlWithFees);
                return availabeCollateral;
            }
        }
    }

    /// @notice Validates if a position should be liquidated based on its collateralization ratio
    /// @dev Retrieves the position details and calculates the current collateralization
    /// @dev Returns true if position should be liquidated, along with current collateral value
    /// @dev Position is liquidatable if current collateral is negative or below minimum required
    /// @param key The key of the position to check for liquidation
    /// @param _price The current price of the index token
    /// @param _fundingFee The funding fee amount (positive means trader receives, negative means trader pays)
    /// @param _borrowFee The borrowing fee amount charged to the trader
    /// @param _liquidationFee The liquidation fee amount that would be charged during liquidation
    /// @return isLiquidable True if the position should be liquidated, false otherwise
    /// @return currentCollateral The current collateral value after applying all fees and PnL
    function validateliquidation(
        bytes32 key,
        uint256 _price,
        int256 _fundingFee,
        uint256 _borrowFee,
        uint256 _liquidationFee
    ) public view returns (bool isLiquidable, int256 currentCollateral) {
        address _contractAddr = address(this);
        Position memory position = IViewFacet(_contractAddr).getPosition(key);

        currentCollateral = getCurrentCollateral(key, _price, _fundingFee, _borrowFee, _liquidationFee);
        if (currentCollateral > 0) {
            if (
                convertToInt256ToUint256(currentCollateral)
                    <= (position.size / s.liquidationLeverage[position.indexToken])
            ) {
                return (true, currentCollateral);
            } else {
                return (false, currentCollateral);
            }
        } else {
            // means protocol liquidator call
            return (true, currentCollateral);
        }
    }

    /// @notice Adds LP fees to the protocol
    /// @dev Only callable by keeper. Converts feesUSD from 18 decimals to 6 decimals for USDC transfer,
    ///      then converts back to 18 decimals for compartment balance update
    /// @param feesUSD The amount of fees in USD (18 decimals)
    /// @param _indexToken The address of the index token to add fees for
    function addLPFees(uint256 feesUSD, address _indexToken) public onlyKeeper {
        address _contractAddr = address(this);
        uint256 dnFeeUSD = feesUSD / 10 ** 12;
        uint256 prvBalance = IERC20(s.usdc).balanceOf(_contractAddr);
        IERC20(s.usdc).safeTransferFrom(msg.sender, _contractAddr, dnFeeUSD);
        uint256 postBalance = IERC20(s.usdc).balanceOf(_contractAddr);
        feesUSD = (postBalance - prvBalance) * 10 ** 12;
        increaseCompartmentBal(_indexToken, feesUSD);
        emit LPFeesAdded(feesUSD, _indexToken);
    }

    // ========================== View and Pure Functions ========================== //

    /// @notice Calculates the next average price after a position size change
    /// @param _size The current position size
    /// @param _averagePrice The current average price
    /// @param _isLong Whether the position is long (true) or short (false)
    /// @param _nextPrice The new price to factor into the average
    /// @param _indexDelta The size change to calculate for
    /// @return nextAvgPrice The newly calculated average price
    function getNextAveragePrice(
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _nextPrice,
        uint256 _indexDelta
    ) public pure returns (uint256 nextAvgPrice) {
        (bool hasProfit, uint256 delta) = getDelta(_size, _averagePrice, _isLong, _nextPrice);
        uint256 nextSize = _size + _indexDelta;

        uint256 divisor;
        if (_isLong) {
            divisor = hasProfit ? nextSize + delta : nextSize - delta;
        } else {
            divisor = hasProfit ? nextSize - delta : nextSize + delta;
        }

        return (_nextPrice * nextSize) / divisor;
    }

    /// @notice Calculates the profit/loss delta for a position
    /// @param _size The position size
    /// @param _averagePrice The position's average entry price
    /// @param _isLong Whether position is long (true) or short (false)
    /// @param _price The current price
    /// @return hasProfit Whether the position is in profit
    /// @return delta The absolute profit/loss amount
    function getDelta(uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _price)
        public
        pure
        returns (bool hasProfit, uint256 delta)
    {
        require(_averagePrice != 0, TradeFacet__AvgPriceIsZero());
        uint256 price = _price;

        uint256 priceDelta = _averagePrice > price ? _averagePrice - price : price - _averagePrice;
        delta = (_size * (priceDelta)) / (_averagePrice); // 1000 * 2000 /10000 = 200, 1000*1.873/10 = 187.3

        if (_isLong) {
            hasProfit = price > _averagePrice;
        } else {
            hasProfit = _averagePrice > price;
        }

        return (hasProfit, delta);
    }

    /// @notice Calculates position size and price that would trigger liquidation
    /// @param key The position's unique identifier
    /// @param fees The fees to factor into calculation
    /// @return liquidationPositionSize The position size that would trigger liquidation
    /// @return liquidationPrice The price at which liquidation would occur
    function getTransferPositionSizeAndPrice(bytes32 key, int256 fees)
        public
        view
        returns (uint256 liquidationPositionSize, uint256 liquidationPrice)
    {
        uint256 effectiveCollateral;
        Position memory position = IViewFacet(address(this)).getPosition(key);
        require(position.size != 0, TradeFacet__PositionNotExist());
        uint256 numberOfTokens = (position.size * 1e18) / position.averagePrice;
        uint256 uFee = convertToInt256ToUint256(fees);
        if (fees < 0) {
            effectiveCollateral = position.collateral - uFee;
        } else {
            effectiveCollateral = position.collateral + uFee;
        }
        if (position.isLong) {
            liquidationPositionSize =
                position.size - (effectiveCollateral - (position.size / s.liquidationLeverage[position.indexToken]));
        } else {
            liquidationPositionSize =
                position.size + (effectiveCollateral - (position.size / s.liquidationLeverage[position.indexToken]));
        }
        liquidationPrice = (liquidationPositionSize * 1e18) / numberOfTokens;
    }

    /// @notice Gets the position size and price that would trigger liquidation
    /// @param key The position's unique identifier
    /// @return liquidationPositionSize The position size that would trigger liquidation
    /// @return liquidationPrice The price at which liquidation would occur
    function getLiquidationPositionSizeAndPrice(bytes32 key)
        public
        view
        returns (uint256 liquidationPositionSize, uint256 liquidationPrice)
    {
        Position memory position = IViewFacet(address(this)).getPosition(key);
        require(position.size != 0, TradeFacet__PositionNotExist());
        uint256 numberOfTokens = (position.size * 1e18) / position.averagePrice;

        if (position.isLong) {
            liquidationPositionSize =
                position.size - (position.collateral - (position.size / s.liquidationLeverage[position.indexToken]));
        } else {
            liquidationPositionSize =
                position.size + (position.collateral - (position.size / s.liquidationLeverage[position.indexToken]));
        }
        liquidationPrice = (liquidationPositionSize * 1e18) / numberOfTokens;
    }

    /// @notice Calculates maximum available USDC for an address
    /// @param _address The address to check available USDC for
    /// @return maxAvailUsdc The maximum available USDC amount
    function maxAvailableUSDC(address _address) public view returns (uint256 maxAvailUsdc) {
        Compartment memory compartment = s.compartments[_address];
        return (
            ((compartment.balance + s.borrowedAmountFromPool[_address].total) * s.optimalUtilization[_address])
                / BASIS_POINTS_DIVISOR
        ) - s.borrowedAmountFromPool[_address].total;
    }

    // ========================== Internal Functions ========================== //

    /// @notice Converts an int256 to uint256, ensuring the number is positive
    /// @param num The int256 number to convert
    /// @return _posNum The converted positive uint256
    function convertToInt256ToUint256(int256 num) internal pure returns (uint256 _posNum) {
        if (num < 0) {
            num = -num;
        }
        return uint256(num);
    }

    /// @notice Converts a uint256 to a negative int256
    /// @param num The uint256 to convert to negative
    /// @return _intNum The converted negative int256
    function toNegativeInt256(uint256 num) internal pure returns (int256 _intNum) {
        require(num <= uint256(type(int256).max), TradeFacet__MaxIntValueExceeded());
        if (num == 0) {
            return 0;
        }
        return -int256(num);
    }

    /// @notice Internal function to distribute borrow fees
    /// @param indexToken The token to distribute borrow fees for
    /// @param borrowFee The borrow fee amount to distribute
    function _borrowFeeDistribution(address indexToken, uint256 borrowFee) internal {
        uint256 dnBorrowFee = borrowFee / 10 ** 12;
        IERC20(s.usdc).approve(s.keeper, dnBorrowFee);
        IKeeper(s.keeper).distributeBorrowingFees(indexToken, borrowFee);
    }

    /// @notice Internal function to distribute funding fees
    /// @param indexToken The token to distribute funding fees for
    /// @param keys Array of position keys to distribute to
    /// @param fundFeeValues Array of funding fee values for each position
    /// @dev Updates position collateral and global long/short collateral based on funding fees
    function _fundingFeeDistribution(address indexToken, bytes32[] memory keys, int256[] memory fundFeeValues)
        internal
    {
        require(keys.length == fundFeeValues.length, TradeFacet__LengthMismatch());
        uint256 length = keys.length;
        int256 longSideCollateral;
        int256 shortSideCollateral;
        int256 netCollateral;

        for (uint256 i = 0; i < length; i++) {
            emit Log("i");
            Position memory position = IViewFacet(address(this)).getPosition(keys[i]);
            if (position.size != 0) {
                uint256 fundingFeeValue = convertToInt256ToUint256(fundFeeValues[i]);
                emit Log("_fundingFeeDist1");
                position.collateral =
                    fundFeeValues[i] > 0 ? position.collateral + fundingFeeValue : position.collateral - fundingFeeValue;

                if (position.isLong) {
                    longSideCollateral += fundFeeValues[i];
                } else {
                    shortSideCollateral += fundFeeValues[i];
                }
                s.positions[keys[i]] = position;
            }
            netCollateral += fundFeeValues[i];
        }
        emit Log("beforeReq");
        emit LogInt(netCollateral, longSideCollateral, shortSideCollateral);
        require(netCollateral <= 1e12, TradeFacet__FundingFeeMismatch());

        emit Log("_fundingFeeDist2");
        s.longCollateral[indexToken] = longSideCollateral > 0
            ? s.longCollateral[indexToken] + convertToInt256ToUint256(longSideCollateral)
            : s.longCollateral[indexToken] - convertToInt256ToUint256(longSideCollateral);
        s.shortCollateral[indexToken] = shortSideCollateral > 0
            ? s.shortCollateral[indexToken] + convertToInt256ToUint256(shortSideCollateral)
            : s.shortCollateral[indexToken] - convertToInt256ToUint256(shortSideCollateral);
    }

    /// @notice Transfers profits to a receiver through the deposit contract
    /// @dev When called from decreasePosition(), USD balance is already settled so no update needed
    /// @param _amount The amount of profit to transfer in USD (18 decimals)
    /// @param _receiver The address to receive the profits
    /// @custom:emits TransferOutProfit event with USDC token, amount and receiver
    function _transferOutProfit(uint256 _amount, address _receiver) internal {
        uint256 dnAmount = _amount / 10 ** 12;
        uint256 prvBalance = IERC20(s.usdc).balanceOf(s.deposit);
        IERC20(s.usdc).safeTransfer(s.deposit, dnAmount);
        uint256 postBalance = IERC20(s.usdc).balanceOf(s.deposit); // deposit contract could recieve less
        _amount = (postBalance - prvBalance) * 10 ** 12;
        IDeposit(s.deposit).transferIn(_receiver, _amount); // #Zokyo-3 #Zokyo-10
        emit TransferOutProfit(s.usdc, _amount, _receiver);
    }

    /// @notice Increases the balance of a compartment
    /// @dev Updates both the compartment's balance and the total USD balance
    /// @param _address The address of the compartment to increase balance for
    /// @param _amount The amount to increase the balance by (in USD with 18 decimals)
    function increaseCompartmentBal(address _address, uint256 _amount) internal {
        Compartment memory compartment = s.compartments[_address];
        compartment.balance = compartment.balance + _amount;
        s.compartments[_address] = compartment;
        s.usdBalance = s.usdBalance + _amount;
        emit CompartmentBalanceIncreased(_address, _amount);
    }

    /// @notice Decreases the balance of a compartment
    /// @dev Updates both the compartment's balance and the total USD balance
    /// @param _address The address of the compartment to decrease balance for
    /// @param _amount The amount to decrease the balance by (in USD with 18 decimals)
    function reduceCompartmentBal(address _address, uint256 _amount) internal {
        Compartment memory compartment = s.compartments[_address]; // 12k
        compartment.balance = compartment.balance - _amount; // 440
        s.compartments[_address] = compartment;
        s.usdBalance = s.usdBalance - _amount; // 24K - 440
        emit CompartmentBalanceReduced(_address, _amount);
    }

    // ========================== Private Functions ========================== //
    /// @notice Internal function to increase a position or add collateral to an existing position
    /// @dev Handles both creating new positions and modifying existing ones
    /// @param _incPosParams The parameters for increasing the position including:
    ///        - account: Address of the position owner
    ///        - indexToken: Address of the token being traded
    ///        - collateralDelta: Amount of collateral to add
    ///        - indexDelta: Size increase for the position
    ///        - isLong: Whether position is long (true) or short (false)
    ///        - price: Price at which to execute the increase
    ///        - tradeFee: Fee charged for the trade
    /// @return Position The updated position after the increase
    function _increasePosition(PositionParams memory _incPosParams) private returns (Position memory) {
        address _contractAddr = address(this);
        require(s.isIndexToken[_incPosParams.indexToken], TradeFacet__InvalidAsset());
        require(
            _incPosParams.borrowFee == 0 && _incPosParams.fundingFee == 0,
            IncreasePosition_IncorrectBorrowAndFundingFee()
        );
        require(_incPosParams.collateralDelta > 0, "Error");
        IDeposit(s.deposit).lockForAnOrder(_incPosParams.account, _incPosParams.collateralDelta);
        bytes32 key = IViewFacet(_contractAddr).getPositionKey(
            _incPosParams.account, address(0), _incPosParams.indexToken, _incPosParams.isLong
        );

        Position memory position = s.positions[key];
        if (position.size == 0) {
            // New Position
            position.averagePrice = _incPosParams.price;
            position.creationTime = block.timestamp;
            position.indexToken = _incPosParams.indexToken;
            position.isLong = _incPosParams.isLong;
            emit NewPositionCreated(key);
        }
        position.lastIncreasedTime = block.timestamp;

        if (position.size != 0 && _incPosParams.indexDelta != 0) {
            // Increasing an Existing Position
            position.averagePrice = getNextAveragePrice(
                position.size,
                position.averagePrice,
                _incPosParams.isLong,
                _incPosParams.price,
                _incPosParams.indexDelta
            );
        }

        if (_incPosParams.indexDelta != 0) {
            position.size = position.size + _incPosParams.indexDelta;
        }

        // @note - increasePosition (MatchOrders) and IncreaseCollateral
        if (_incPosParams.collateralDelta != 0) {
            require(position.size != 0, TradeFacet__NonZeroPositionSizeNeeded());
            position.collateral += _incPosParams.collateralDelta;
        }

        // Only During increasePosition and not during increaseCollateral
        if (_incPosParams.traderType != TraderType.None) {
            if (_incPosParams.tradeFee > 0) {
                IERC20(s.usdc).approve(s.keeper, _incPosParams.tradeFee);
                IKeeper(s.keeper).distributeTradeFees(
                    _incPosParams.tradeFee, _incPosParams.indexToken, _incPosParams.account
                );
                position.tradingFee += _incPosParams.tradeFee;
            }
        }

        // @note - increasePosition (MatchOrders && MatchWithPool) and (tradeFees != 0)
        if (_incPosParams.traderType != TraderType.None && _incPosParams.tradeFee != 0) {
            require(position.collateral >= _incPosParams.tradeFee, TradeFacet__FeeLargerThanCollateral());
            emit Log("increasePosition1");
            position.collateral -= _incPosParams.tradeFee;
        }

        emit TotalTradingFees(
            _incPosParams.account,
            _incPosParams.traderType,
            int256(_incPosParams.tradeFee),
            _incPosParams.tradeFee,
            0,
            0,
            block.timestamp
        );

        if (_incPosParams.matchType == MatchType.MatchWithPool) {
            require(
                _incPosParams.indexDelta < maxAvailableUSDC(_incPosParams.indexToken),
                TradeFacet__IndexDeltaMoreThanMaxUsdc()
            );
            position.reserveAmount += _incPosParams.indexDelta;
            s.borrowedAmountFromPool[_incPosParams.indexToken].total += _incPosParams.indexDelta;
            if (_incPosParams.isLong) {
                s.borrowedAmountFromPool[_incPosParams.indexToken].long += _incPosParams.indexDelta;
            } else {
                s.borrowedAmountFromPool[_incPosParams.indexToken].short += _incPosParams.indexDelta;
            }
            uint256 combPoolBalanceBefore = s.usdBalance;
            uint256 compartmentBalanceBefore = s.compartments[_incPosParams.indexToken].balance;
            uint256 totalBorrowedBefore = s.totalBorrowedUSD;
            reduceCompartmentBal(_incPosParams.indexToken, _incPosParams.indexDelta);

            s.totalBorrowedUSD = s.totalBorrowedUSD + _incPosParams.indexDelta;
            emit DecreaseCOMBPoolBalance(
                _incPosParams.indexToken,
                _incPosParams.account,
                _incPosParams.traderType,
                _incPosParams.indexDelta,
                combPoolBalanceBefore,
                s.usdBalance,
                compartmentBalanceBefore,
                s.compartments[_incPosParams.indexToken].balance,
                totalBorrowedBefore,
                s.totalBorrowedUSD,
                block.timestamp
            );
        } else if (_incPosParams.matchType == MatchType.MatchOrders) {
            s.lastTradedPrice[_incPosParams.indexToken] = _incPosParams.price;
            position.viaOrder = position.viaOrder + _incPosParams.indexDelta;
            s.totalOBTradedSize[_incPosParams.indexToken] =
                s.totalOBTradedSize[_incPosParams.indexToken] + _incPosParams.indexDelta;
        }
        // @audit - PVE004 - Fix, added check for collateralDelta > tradeFee
        require(_incPosParams.collateralDelta > _incPosParams.tradeFee, "TradeFacet__TradeFeeLargerThanCollateralDelta");
        if (_incPosParams.isLong) {
            s.longCollateral[_incPosParams.indexToken] += _incPosParams.collateralDelta - _incPosParams.tradeFee;
        } else {
            s.shortCollateral[_incPosParams.indexToken] += _incPosParams.collateralDelta - _incPosParams.tradeFee;
        }

        // if (_incPosParams.traderType != TraderType.None) {
        //     updateReserve(_incPosParams);
        // }

        emit IncreasePosition(
            key,
            _incPosParams.account,
            _incPosParams.indexToken,
            _incPosParams.collateralDelta,
            _incPosParams.indexDelta,
            _incPosParams.isLong,
            _incPosParams.price,
            int256(_incPosParams.tradeFee),
            true,
            _incPosParams.orderId
        );

        emit UpdatePosition(
            key,
            position.size,
            position.indexToken,
            position.collateral,
            position.averagePrice,
            position.reserveAmount,
            position.viaOrder,
            position.realisedPnl,
            _incPosParams.price,
            _incPosParams.orderId,
            _incPosParams.account,
            position.creationTime
        );

        emit CurrentRealisedPnL(
            key,
            _incPosParams.account,
            position.indexToken,
            _incPosParams.indexDelta,
            _incPosParams.isLong,
            0,
            _incPosParams.orderId
        );

        s.positions[key] = position;
        return position;
    }
    /// @notice Decreases the position for a given index token and updates the relevant states
    /// @dev This function handles the decrease of a position by adjusting collateral, size and reserved amounts
    /// @dev It also distributes trade fees and checks liquidation conditions
    /// @dev Emits events for position updates and closure
    /// @param _decPosParams Parameters for decreasing the position (DecreaseParameters struct)
    /// @return uint256 The amount of USD after deducting fees

    function _decreasePosition(PositionParams memory _decPosParams) private returns (uint256) {
        // bool isFullyRebated;
        uint256 totalFees; // Sum of TradeFee and BorrowFee only
        uint256 usdOut;
        uint256 collateralToReturn;
        int256 currentRealisedPnL;
        require(s.isIndexToken[_decPosParams.indexToken], TradeFacet__InvalidAsset());
        bytes32 key = IViewFacet(address(this)).getPositionKey(
            _decPosParams.account, address(0), _decPosParams.indexToken, _decPosParams.isLong
        );

        Position storage position = s.positions[key];
        require(position.size != 0, TradeFacet__NonZeroPositionSizeNeeded());
        require(position.size >= _decPosParams.indexDelta, TradeFacet__IndexDeltaMoreThanSize());
        require(position.collateral >= _decPosParams.collateralDelta, TradeFacet__DeltaLessThanCollateral());
        if (_decPosParams.traderType == TraderType.None) {
            // @note - decrease collateral
            require(
                _decPosParams.tradeFee == 0 && (_decPosParams.borrowFee == 0 && _decPosParams.fundingFee == 0),
                TradeFacet__IncorrectFeeCondition()
            );
        } else {
            // require(_decPosParams.borrowFee > 0, TradeFacet__IncorrectBorrowFee()); // Borrow Fee can be Zero if
            // closed within 10 mins.
            if (!s.isProtocolLiquidator[msg.sender]) {
                if (_decPosParams.tradeFee > 0) {
                    IERC20(s.usdc).approve(s.keeper, _decPosParams.tradeFee);
                    IKeeper(s.keeper).distributeTradeFees(
                        _decPosParams.tradeFee, _decPosParams.indexToken, _decPosParams.account
                    );
                    position.tradingFee += _decPosParams.tradeFee;
                }
            }
        }
        totalFees = _decPosParams.borrowFee + _decPosParams.tradeFee;
        require(position.collateral > totalFees, TradeFacet__FeeLargerThanCollateral());

        position.collateral = position.collateral - totalFees;
        if (_decPosParams.collateralDelta == 0) {
            (usdOut, collateralToReturn, currentRealisedPnL) = _reduceCollateral(
                key,
                _decPosParams.indexDelta,
                _decPosParams.collateralDelta,
                _decPosParams.price,
                _decPosParams.fundingFee,
                _decPosParams.account,
                _decPosParams.matchType,
                _decPosParams.traderType
            );
        }

        if (_decPosParams.matchType == MatchType.MatchOrders) {
            if (_decPosParams.collateralDelta != 0) {
                uint256 collateralOnRemoval = position.collateral - _decPosParams.collateralDelta;
                    // Calculate position value using current market price instead of average price
                uint256 positionValueAtMarketPrice = (position.size * 1e18) / _decPosParams.price;
                require(
                    ((positionValueAtMarketPrice * 1e18) / collateralOnRemoval) <= s.maxLeverage,
                    TradeFacet__ExceedsMaxAllowedLeverage()
                );
                require(_decPosParams.indexDelta == 0, "Error");
                position.collateral = position.collateral - _decPosParams.collateralDelta;
                usdOut = _decPosParams.collateralDelta;
            }
            s.lastTradedPrice[_decPosParams.indexToken] = _decPosParams.price;
            position.viaOrder = position.viaOrder - _decPosParams.indexDelta;
            s.totalOBTradedSize[_decPosParams.indexToken] =
                s.totalOBTradedSize[_decPosParams.indexToken] - _decPosParams.indexDelta;
            if (position.isLong) {
                emit Log("decreasePosition1");
                emit LogUint(totalFees, usdOut, totalFees + usdOut);
                emit LogUint(s.longCollateral[_decPosParams.indexToken], 0, 0);
                // @audit - PVE005 - We don't charge trade fees for decrease collateral (collateralDelta != 0)
                s.longCollateral[_decPosParams.indexToken] -=
                    _decPosParams.collateralDelta == 0 ? totalFees + usdOut : _decPosParams.collateralDelta;
                if (_decPosParams.fundingFee > 0) {
                    emit Log("decreasePosition2");
                    s.shortCollateral[_decPosParams.indexToken] -= convertToInt256ToUint256(_decPosParams.fundingFee);
                } else {
                    s.shortCollateral[_decPosParams.indexToken] += convertToInt256ToUint256(_decPosParams.fundingFee);
                }
            } else {
                emit Log("decreasePosition3");
                emit LogUint(totalFees, usdOut, totalFees + usdOut);
                emit LogUint(s.shortCollateral[_decPosParams.indexToken], 0, 0);
                s.shortCollateral[_decPosParams.indexToken] -=
                    _decPosParams.collateralDelta == 0 ? totalFees + usdOut : _decPosParams.collateralDelta;
                if (_decPosParams.fundingFee > 0) {
                    emit Log("decreasePosition4");
                    s.longCollateral[_decPosParams.indexToken] -= convertToInt256ToUint256(_decPosParams.fundingFee);
                } else {
                    s.longCollateral[_decPosParams.indexToken] += convertToInt256ToUint256(_decPosParams.fundingFee);
                }
            }
        } else if (_decPosParams.matchType == MatchType.MatchWithPool) {
            position.reserveAmount = position.reserveAmount - _decPosParams.indexDelta;
            uint256 combPoolBalanceBefore = s.usdBalance;
            uint256 compartmentBalanceBefore = s.compartments[_decPosParams.indexToken].balance;
            uint256 totalBorrowedBefore = s.totalBorrowedUSD;
            // if (currentRealisedPnL <= int256(_decPosParams.indexDelta)) {
            //     // Unless Extreme Profit Scenario
            //     increaseCompartmentBal(_decPosParams.indexToken, _decPosParams.indexDelta);
            // }
            emit Log("decreasePosition5");
            s.borrowedAmountFromPool[_decPosParams.indexToken].total =
                s.borrowedAmountFromPool[_decPosParams.indexToken].total - _decPosParams.indexDelta;
            if (_decPosParams.isLong) {
                s.borrowedAmountFromPool[_decPosParams.indexToken].long =
                    s.borrowedAmountFromPool[_decPosParams.indexToken].long - _decPosParams.indexDelta;
            } else {
                s.borrowedAmountFromPool[_decPosParams.indexToken].short =
                    s.borrowedAmountFromPool[_decPosParams.indexToken].short - _decPosParams.indexDelta;
            }
            s.totalBorrowedUSD = s.totalBorrowedUSD - _decPosParams.indexDelta;

            if (_decPosParams.isLong) {
                s.longCollateral[_decPosParams.indexToken] -= totalFees;
            } else {
                s.shortCollateral[_decPosParams.indexToken] -= totalFees;
            }
            // @audit - PVE005 - 2 - Fix
            emit Log("decreasePosition6");
            if (position.isLong) {
                if (_decPosParams.fundingFee > 0) {
                    s.longCollateral[_decPosParams.indexToken] -= convertToInt256ToUint256(_decPosParams.fundingFee);
                } else {
                    s.longCollateral[_decPosParams.indexToken] += convertToInt256ToUint256(_decPosParams.fundingFee);
                }
            } else {
                if (_decPosParams.fundingFee > 0) {
                    s.shortCollateral[_decPosParams.indexToken] -= convertToInt256ToUint256(_decPosParams.fundingFee);
                } else {
                    s.shortCollateral[_decPosParams.indexToken] += convertToInt256ToUint256(_decPosParams.fundingFee);
                }
            }

            emit IncreaseCOMBPoolBalance(
                _decPosParams.indexToken,
                _decPosParams.account,
                _decPosParams.traderType,
                _decPosParams.indexDelta,
                combPoolBalanceBefore,
                s.usdBalance,
                compartmentBalanceBefore,
                s.compartments[_decPosParams.indexToken].balance,
                totalBorrowedBefore,
                s.totalBorrowedUSD,
                block.timestamp
            );
        }

        emit TotalTradingFees(
            _decPosParams.account,
            _decPosParams.traderType,
            int256(totalFees),
            _decPosParams.tradeFee,
            _decPosParams.borrowFee,
            _decPosParams.fundingFee,
            block.timestamp
        );
        position.size = position.size - _decPosParams.indexDelta;

        emit UpdatePosition(
            key,
            position.size,
            position.indexToken,
            position.collateral,
            position.averagePrice,
            position.reserveAmount,
            position.viaOrder,
            position.realisedPnl,
            _decPosParams.price,
            _decPosParams.orderId,
            _decPosParams.account,
            position.creationTime
        );

        s.positions[key] = position;

        // if (_decPosParams.traderType != TraderType.None) {
        //     if (_decPosParams.isLong) {
        //         _decreaseGlobalLongSize(_decPosParams.indexToken, (_decPosParams.indexDelta) /
        // (position.averagePrice));
        //     } else {
        //         _decreaseGlobalShortSize(_decPosParams.indexToken, (_decPosParams.indexDelta) /
        // (position.averagePrice));
        //     }
        // }

        emit DecreasePosition(
            key,
            _decPosParams.account,
            _decPosParams.indexToken,
            _decPosParams.collateralDelta,
            _decPosParams.indexDelta,
            _decPosParams.isLong,
            _decPosParams.price,
            int256(totalFees),
            false,
            _decPosParams.orderId,
            _decPosParams.borrowFee,
            _decPosParams.fundingFee
        );

        if (position.size <= s.dustSize) {
            emit ClosePosition(
                key,
                position.size,
                position.indexToken,
                position.collateral,
                position.averagePrice,
                position.reserveAmount,
                position.viaOrder,
                position.realisedPnl,
                _decPosParams.orderId
            );

            // @audit - N1-2 - Yes, it's fixed
            // if (position.size <= s.dustSize) {
            _transferOutProfit(position.collateral, _decPosParams.account);
            // }

            delete s.positions[key];
        }

        if (usdOut != 0) {
            _transferOutProfit(usdOut, _decPosParams.account);
        }
        emit CurrentRealisedPnL(
            key,
            _decPosParams.account,
            _decPosParams.indexToken,
            _decPosParams.indexDelta,
            _decPosParams.isLong,
            currentRealisedPnL,
            _decPosParams.orderId
        );
        return usdOut;
    }

    /// @notice Reduces collateral and calculates profit or loss for a position
    /// @dev Adjusts position collateral based on trading outcomes including:
    ///      - Funding fees
    ///      - Realized profits/losses
    ///      - Collateral pool transfers
    /// @dev Updates position's collateral, realized PnL and transfers between long/short pools
    /// @param key Unique identifier for the position
    /// @param _sizeDelta Amount to change the position size by
    /// @param _collateralDelta Amount to change the collateral by
    /// @param _price Current price of the index token
    /// @param _fundingFee Funding fee amount (can be positive or negative)
    /// @param _account Address of the trader
    /// @param _matchType Type of match (MatchWithPool or MatchOrders)
    /// @param _traderType Type of trader (Maker, Taker, None)
    /// @return uint256 Amount of USD out before fees
    /// @return uint256 Amount of collateral to return
    /// @return int256 Current realized PnL
    function _reduceCollateral(
        bytes32 key,
        uint256 _sizeDelta,
        uint256 _collateralDelta,
        uint256 _price,
        int256 _fundingFee,
        address _account,
        MatchType _matchType,
        TraderType _traderType
    ) private returns (uint256, uint256, int256) {
        uint256 adjustedDelta;
        uint256 usdOut;
        int256 currentRealisedPnL;
        uint256 collateralToReturn;
        Position memory position = s.positions[key];
        uint256 uFundingFee = convertToInt256ToUint256(_fundingFee);

        emit Log("reduceCollateral1");
        if (_fundingFee < 0) {
            position.collateral = position.collateral - uFundingFee;
        } else {
            position.collateral = position.collateral + uFundingFee;
        }

        (bool hasProfit, uint256 delta) = getDelta(position.size, position.averagePrice, position.isLong, _price);

        adjustedDelta = ((_sizeDelta * (delta)) / (position.size)); // 500 * 200 / 1000 = 100

        if (hasProfit && adjustedDelta != 0) {
            // If profit exists
            position.realisedPnl = position.realisedPnl + int256(adjustedDelta);
            currentRealisedPnL = int256(adjustedDelta);

            if (_matchType == MatchType.MatchWithPool) {
                uint256 combPoolBalanceBefore = s.usdBalance; // 24K
                uint256 compartmentBalanceBefore = s.compartments[position.indexToken].balance; //12K
                uint256 totalBorrowedBefore = s.totalBorrowedUSD; // 400
                increaseCompartmentBal(position.indexToken, _sizeDelta);
                reduceCompartmentBal(position.indexToken, adjustedDelta); //480
                usdOut = adjustedDelta;
                emit DecreaseCOMBPoolBalance(
                    position.indexToken,
                    _account,
                    _traderType,
                    adjustedDelta,
                    combPoolBalanceBefore,
                    s.usdBalance,
                    compartmentBalanceBefore,
                    s.compartments[position.indexToken].balance,
                    totalBorrowedBefore,
                    s.totalBorrowedUSD,
                    block.timestamp
                );
            } else {
                usdOut = adjustedDelta; // this is profit share only //
                emit Log("reduceCollateral2");
                if (position.isLong) {
                    s.longCollateral[position.indexToken] += adjustedDelta;
                } else {
                    s.shortCollateral[position.indexToken] += adjustedDelta;
                }
            }
        }
        emit Profit(position.indexToken, adjustedDelta, hasProfit);

        if (!hasProfit && adjustedDelta != 0) {
            require(position.collateral >= adjustedDelta, TradeFacet__LossMoreThanPositionCollateral());
            position.collateral = position.collateral - adjustedDelta; //2000 - 100 = 100
            position.realisedPnl = position.realisedPnl - int256(adjustedDelta); //-100
            currentRealisedPnL = toNegativeInt256(adjustedDelta); // -100
            if (_matchType == MatchType.MatchWithPool) {
                uint256 combPoolBalanceBefore = s.usdBalance;
                uint256 compartmentBalanceBefore = s.compartments[position.indexToken].balance;
                uint256 totalBorrowedBefore = s.totalBorrowedUSD;
                increaseCompartmentBal(position.indexToken, adjustedDelta + _sizeDelta); // 200
                emit IncreaseCOMBPoolBalance(
                    position.indexToken,
                    _account,
                    _traderType,
                    adjustedDelta,
                    combPoolBalanceBefore,
                    s.usdBalance,
                    compartmentBalanceBefore,
                    s.compartments[position.indexToken].balance,
                    totalBorrowedBefore,
                    s.totalBorrowedUSD,
                    block.timestamp
                );
            }
            else {
                 if (position.isLong) {
                    s.longCollateral[position.indexToken] -= adjustedDelta;
                } else {
                    s.shortCollateral[position.indexToken] -= adjustedDelta;
                }
            }
        }
        if (_sizeDelta == position.size) {
            // Complete Position Closure
            usdOut = usdOut + position.collateral;
            position.collateral = 0;
        } else if (_collateralDelta == 0) {
            // Partial Closure only but not Reduce Collateral
            emit Log("reduceCollateral3");

            uint256 newLeverage = (position.size * 1e18) / position.collateral;
            uint256 afterCollateral = (position.size - _sizeDelta) * 1e18 / newLeverage;
            require(position.collateral >= afterCollateral, TradeFacet__LowCollateral());
            collateralToReturn = position.collateral - afterCollateral;
            usdOut = usdOut + collateralToReturn;
            position.collateral = afterCollateral;
        }
        s.positions[key] = position;

        return (usdOut, collateralToReturn, currentRealisedPnL);
    }

}
