// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { Position, TransactionType } from "./interfaces/ICommon.sol";
import { IRouter } from "./interfaces/IRouter.sol";
import { ITradeFacet } from "./interfaces/ITradeFacet.sol";
import { IVaultFacet } from "./interfaces/IVaultFacet.sol";
import { IViewFacet } from "./interfaces/IViewFacet.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title Router
 * @dev Contract handling order matching and transaction processing for a decentralized exchange.
 * @notice This contract is responsible for processing transactions and matching orders in a decentralized exchange.
 * It ensures that only authorized sequencers can process transactions and handles both order matching and pool
 * matching.
 */
contract Router is IRouter, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    address private diamond;

    // ========================== Errors ========================== //

    error Router__InvalidOrder(uint256 matchId);
    error Router__UnauthorizedSequencer();
    error Router__InvalidTransactionData();

    // ========================== Events ========================== //

    event TransactionProcessed(bool taker, bool maker, bool pool, uint256 matchId);
    event Log(string message);
    event LogBytes(bytes bytesData);
    event DiamondUpdated(address newDiamond);

    // ========================== Modifiers ========================== //
    modifier onlySequencer() {
        bool isSequencerWhitelist = IViewFacet(diamond).isSequencerWhitelisted(msg.sender);
        require(isSequencerWhitelist, Router__UnauthorizedSequencer());
        _;
    }
    // ========================== Functions ========================== //

    // ========================== External Functions ========================== //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() payable {
        _disableInitializers();
    }

    /**
     * @notice Processes a batch of transactions atomically.
     * @param transactions Array of transaction data.
     */
    function batchProcessData(bytes[] calldata transactions) external nonReentrant whenNotPaused onlySequencer {
        uint256 length = transactions.length;
        for (uint256 i = 0; i < length;) {
            _processTransaction(transactions[i]);
            unchecked {
                ++i;
            }
        }
    }

    // ========================== Public Functions ========================== //

    /**
     * @notice Initializes the contract with the given diamond address.
     */
    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Pauses the contract, preventing certain functions from being executed.
     */
    function pause() external payable onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing certain functions to be executed.
     */
    function unpause() external payable onlyOwner {
        _unpause();
    }

    /**
     * @notice Set the diamond contract address
     * @param _diamond The address of the diamond contract
     */
    function setDiamondContract(address _diamond) external payable onlyOwner {
        if (diamond != _diamond) {
            diamond = _diamond;
            emit DiamondUpdated(_diamond);
        }
    }

    /**
     * @notice Processes a single transaction.
     * @param transaction Transaction data.
     */
    function processTransaction(bytes calldata transaction) external nonReentrant whenNotPaused onlySequencer {
        return _processTransaction(transaction);
    }

    // ========================== Internal Functions ========================== //
    /**
     * @dev Authorizes the upgrade to a new implementation.
     * @param newImplementation Address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /**
     * @dev Internal function to process a transaction based on its type.
     * @param transaction Transaction data.
     */
    function _processTransaction(bytes calldata transaction) internal {
        address _diamond = diamond;
        require(transaction.length > 0, Router__InvalidTransactionData());

        TransactionType txType = TransactionType(uint8(transaction[0]));

        require(
            uint8(txType) >= uint8(TransactionType.MatchOrders) && uint8(txType) <= uint8(TransactionType.MatchWithPool),
            Router__InvalidTransactionData()
        );

        if (txType == TransactionType.MatchOrders) {
            MatchOrders memory order = abi.decode(transaction[1:], (MatchOrders));

            Order memory taker = order.taker;
            Order memory maker = order.maker;

            // // Ensuring both orders are valid.
            if (taker.amount == 0 || maker.amount == 0) {
                revert Router__InvalidOrder(order.matchId);
            }

            if (maker.indexToken != taker.indexToken) revert Router__InvalidOrder(order.matchId);

            if (!maker.reduceOnly) {
                try ITradeFacet(_diamond).increasePosition(
                    ITradeFacet.PositionParams({
                        collateralDelta: maker.collateral,
                        indexDelta: maker.amount,
                        price: maker.priceX18,
                        orderId: order.matchId,
                        tradeFee: maker.tradeFee,
                        borrowFee: maker.borrowFee,
                        fundingFee: maker.fundingFee,
                        account: maker.sender,
                        indexToken: maker.indexToken,
                        matchType: ITradeFacet.MatchType.MatchOrders,
                        traderType: maker.traderType,
                        isLong: maker.isLong
                    })
                ) returns (Position memory) {
                    placeTakerOrder(taker, order.matchId);
                } catch Error(string memory reason) {
                    emit Log(reason);

                    emit TransactionProcessed(true, false, false, order.matchId);
                } catch (bytes memory lowLevelData) {
                    emit LogBytes(lowLevelData);

                    emit TransactionProcessed(true, false, false, order.matchId);
                }
            } else {
                try ITradeFacet(_diamond).decreasePosition(
                    ITradeFacet.PositionParams({
                        collateralDelta: maker.collateral,
                        indexDelta: maker.amount,
                        price: maker.priceX18,
                        orderId: order.matchId,
                        tradeFee: maker.tradeFee,
                        borrowFee: maker.borrowFee,
                        fundingFee: maker.fundingFee,
                        account: maker.sender,
                        indexToken: maker.indexToken,
                        matchType: ITradeFacet.MatchType.MatchOrders,
                        traderType: maker.traderType,
                        isLong: maker.isLong
                    })
                ) returns (uint256) {
                    placeTakerOrder(taker, order.matchId);
                } catch Error(string memory reason) {
                    emit Log(reason);
                    emit TransactionProcessed(true, false, false, order.matchId);
                } catch (bytes memory lowLevelData) {
                    emit LogBytes(lowLevelData);

                    emit TransactionProcessed(true, false, false, order.matchId);
                }
            }
        } else {
            MatchWithPool memory poolOrder = abi.decode(transaction[1:], (MatchWithPool));

            // Extracting the taker order from the MatchWithPool struct.
            Order memory takerOrder = poolOrder.order;
            if (takerOrder.amount == 0) {
                revert Router__InvalidOrder(poolOrder.matchId);
            }

            // Processing the taker's order based on whether it's reduce-only or not.
            if (!takerOrder.reduceOnly) {
                try ITradeFacet(_diamond).increasePosition(
                    ITradeFacet.PositionParams({
                        collateralDelta: takerOrder.collateral,
                        indexDelta: takerOrder.amount,
                        price: takerOrder.priceX18,
                        orderId: poolOrder.matchId,
                        tradeFee: takerOrder.tradeFee,
                        borrowFee: takerOrder.borrowFee,
                        fundingFee: takerOrder.fundingFee,
                        account: takerOrder.sender,
                        indexToken: takerOrder.indexToken,
                        matchType: ITradeFacet.MatchType.MatchWithPool,
                        traderType: takerOrder.traderType,
                        isLong: takerOrder.isLong
                    })
                ) returns (Position memory) {
                    emit TransactionProcessed(false, false, true, poolOrder.matchId);
                } catch Error(string memory reason) {
                    emit Log(reason);
                    revert Router__InvalidOrder(poolOrder.matchId);
                } catch (bytes memory lowLevelData) {
                    emit LogBytes(lowLevelData);
                    emit TransactionProcessed(false, false, false, poolOrder.matchId);
                }
            } else {
                try ITradeFacet(_diamond).decreasePosition(
                    ITradeFacet.PositionParams({
                        collateralDelta: takerOrder.collateral,
                        indexDelta: takerOrder.amount,
                        price: takerOrder.priceX18,
                        orderId: poolOrder.matchId,
                        tradeFee: takerOrder.tradeFee,
                        borrowFee: takerOrder.borrowFee,
                        fundingFee: takerOrder.fundingFee,
                        account: takerOrder.sender,
                        indexToken: takerOrder.indexToken,
                        matchType: ITradeFacet.MatchType.MatchWithPool,
                        traderType: takerOrder.traderType,
                        isLong: takerOrder.isLong
                    })
                ) returns (uint256) {
                    emit TransactionProcessed(false, false, true, poolOrder.matchId);
                } catch Error(string memory reason) {
                    emit Log(reason);
                    revert Router__InvalidOrder(poolOrder.matchId);
                } catch (bytes memory lowLevelData) {
                    emit LogBytes(lowLevelData);
                    emit TransactionProcessed(false, false, false, poolOrder.matchId);
                }
            }
        }
    }

    /**
     * @dev Places a taker order based on the provided order details.
     * @param takerOrder Taker order details.
     * @param matchId Match ID of the order.
     */
    function placeTakerOrder(Order memory takerOrder, uint256 matchId) internal {
        address _diamond = diamond;
        if (!takerOrder.reduceOnly) {
            ITradeFacet(_diamond).increasePosition(
                ITradeFacet.PositionParams({
                    collateralDelta: takerOrder.collateral,
                    indexDelta: takerOrder.amount,
                    price: takerOrder.priceX18,
                    orderId: matchId,
                    tradeFee: takerOrder.tradeFee,
                    borrowFee: takerOrder.borrowFee,
                    fundingFee: takerOrder.fundingFee,
                    account: takerOrder.sender,
                    indexToken: takerOrder.indexToken,
                    matchType: ITradeFacet.MatchType.MatchOrders,
                    traderType: takerOrder.traderType,
                    isLong: takerOrder.isLong
                })
            );
        } else {
            ITradeFacet(_diamond).decreasePosition(
                ITradeFacet.PositionParams({
                    collateralDelta: takerOrder.collateral,
                    indexDelta: takerOrder.amount,
                    price: takerOrder.priceX18,
                    orderId: matchId,
                    tradeFee: takerOrder.tradeFee,
                    borrowFee: takerOrder.borrowFee,
                    fundingFee: takerOrder.fundingFee,
                    account: takerOrder.sender,
                    indexToken: takerOrder.indexToken,
                    matchType: ITradeFacet.MatchType.MatchOrders,
                    traderType: takerOrder.traderType,
                    isLong: takerOrder.isLong
                })
            );
        }
        emit TransactionProcessed(true, true, false, matchId);
    }

}
