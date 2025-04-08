// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { LiquidablePositionDetails, Position } from "./interfaces/ICommon.sol";
import { IEscrow } from "./interfaces/IEscrow.sol";
import { ITradeFacet } from "./interfaces/ITradeFacet.sol";
import { IVaultFacet } from "./interfaces/IVaultFacet.sol";
import { IViewFacet } from "./interfaces/IViewFacet.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "hardhat/console.sol";

/**
 * @title Escrow Contract
 * @dev Handles escrow functionality, liquidation, and management of positions.
 * @notice This contract manages the escrow of positions, handles liquidations, and updates position details.
 */
contract Escrow is IEscrow, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    uint256 public liquidablePositionsCount;
    address public usdc;
    address public diamond;
    mapping(bytes32 => Position) public keyToLiquidablePosition;
    mapping(bytes32 => LiquidablePositionDetails) public keyToLiquidablePositionDetails;

    // ========================== Errors ========================== //

    error Escrow__PositionSizeLowerThanCollateral();
    error Escrow__Exceeds20xLeverage();
    error Escrow__NoPositionToLiquidateAcquire();
    error Escrow__LiquidationSlotExpired();
    error Escrow__ProtocolLiquidatorOnly();
    error Escrow__LowCollateral();
    error Escrow_OnlyDiamond();

    // ========================== Events ========================== //

    event TransferPositionEscrowToLiquidator(
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
    event DiamondUpdated(address _newDiamondAddr);

    // ========================== Modifiers ========================== //

    modifier onlyDiamond() {
        require(msg.sender == diamond, Escrow_OnlyDiamond());
        _;
    }

    // ========================== Functions ========================== //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() payable {
        _disableInitializers();
    }

    // ========================== External Functions ========================== //

    /**
     * @dev Pauses contract operations. Only callable by the owner.
     */
    function pause() external payable onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses contract operations. Only callable by the owner.
     */
    function unpause() external payable onlyOwner {
        _unpause();
    }

    /**
     * @dev Sets the address of the diamond contract. Only callable by the owner.
     * @param _diamond The address of the diamond contract.
     */
    function setDiamondContract(address _diamond) external payable onlyOwner {
        // #Zokyo-60
        if (diamond != _diamond) {
            diamond = _diamond;
            emit DiamondUpdated(_diamond);
        }
    }

    /**
     * @dev Updates information for a liquidable position. Only callable by the diamond contract.
     * @param _key The key of the position.
     * @param _collateralRequirement The collateral requirement for liquidation.
     * @param _position The position data.
     */
    function updateAllLiquidablePositions(bytes32 _key, uint256 _collateralRequirement, Position memory _position)
        external
        onlyDiamond
        whenNotPaused
    {
        liquidablePositionsCount = liquidablePositionsCount + 1; // starts from 1
        keyToLiquidablePosition[_key] = _position;
        keyToLiquidablePositionDetails[_key].collateralForLiquidation = _collateralRequirement;
        if (_collateralRequirement == 0) {
            keyToLiquidablePositionDetails[_key].isBadDebtPosition = true;
        }
        keyToLiquidablePositionDetails[_key].positionTransferredTimestamp = block.timestamp;
    }

    /**
     * @notice Transfers a position to the liquidator for liquidation.
     * @dev Can only be called when the contract is not paused.
     * @param _key The key of the position to be liquidated.
     * @param _collateralAmount The amount of collateral to transfer.
     */
    function liquidatePosition(bytes32 _key, uint256 _collateralAmount) external nonReentrant {
        // #Zokyo-25
        address _contractAddress = address(this);
        address _diamond = diamond;
        Position memory escrowPosition = keyToLiquidablePosition[_key]; // escrowPosition
        require(escrowPosition.size != 0, Escrow__NoPositionToLiquidateAcquire());
        LiquidablePositionDetails memory keyToLiqPos = keyToLiquidablePositionDetails[_key];
        uint256 actualCollateralRequired = keyToLiqPos.collateralForLiquidation;
        bytes32 _newKey = getPositionKey(msg.sender, address(0), escrowPosition.indexToken, escrowPosition.isLong); // liquidatorKey
        Position memory liquidatorPosition = IViewFacet(diamond).getPosition(_newKey); // liquidator's position
        uint256 prvBalance;
        uint256 postBalance;
        if (!IViewFacet(diamond).isProtocolLiquidatorAddress(msg.sender)) {
            uint256 interval = block.timestamp - keyToLiqPos.positionTransferredTimestamp;
            require(interval <= 300, Escrow__LiquidationSlotExpired());
            require(!keyToLiqPos.isBadDebtPosition, Escrow__ProtocolLiquidatorOnly());
            require(actualCollateralRequired <= _collateralAmount, Escrow__LowCollateral());
            uint256 positionSize = escrowPosition.size;
            require(positionSize >= _collateralAmount, Escrow__PositionSizeLowerThanCollateral());
            uint256 userleverage = positionSize / (escrowPosition.collateral + _collateralAmount); // need to check
            uint256 maxLiqLeverage = IViewFacet(diamond).getMaxLiquidatorLeverageToAcquirePosition();
            require(userleverage <= maxLiqLeverage, Escrow__Exceeds20xLeverage());
            // liquidator should have given approval for _collateralAmount
            uint256 denormalizedCollateral = _collateralAmount / 10 ** 12;
            prvBalance = IERC20(usdc).balanceOf(_contractAddress);
            IERC20(usdc).safeTransferFrom(msg.sender, _contractAddress, denormalizedCollateral);
            postBalance = IERC20(usdc).balanceOf(_contractAddress);
            // @audit - PVE007 - fix, added collateral to position in 175 and 188 line
            IERC20(usdc).safeTransfer(_diamond, postBalance - prvBalance);
        }

        Position memory _newPosition;

        if (
            escrowPosition.indexToken == liquidatorPosition.indexToken
                && escrowPosition.isLong == liquidatorPosition.isLong
        ) {
            uint256 _nextAvgPrice = ITradeFacet(diamond).getNextAveragePrice(
                liquidatorPosition.size,
                liquidatorPosition.averagePrice,
                escrowPosition.isLong,
                escrowPosition.averagePrice,
                escrowPosition.size
            );

            _newPosition = Position({
                size: escrowPosition.size + liquidatorPosition.size,
                collateral: escrowPosition.collateral + liquidatorPosition.collateral + ((postBalance - prvBalance) * 1e12),
                averagePrice: _nextAvgPrice,
                reserveAmount: escrowPosition.reserveAmount + liquidatorPosition.reserveAmount,
                viaOrder: escrowPosition.viaOrder + liquidatorPosition.viaOrder,
                realisedPnl: escrowPosition.realisedPnl + liquidatorPosition.realisedPnl,
                isLong: liquidatorPosition.isLong,
                lastIncreasedTime: block.timestamp,
                indexToken: liquidatorPosition.indexToken,
                creationTime: liquidatorPosition.creationTime,
                tradingFee: escrowPosition.tradingFee + liquidatorPosition.tradingFee
            });
            IVaultFacet(diamond).updatePositionForLiquidator(_key, _newKey, _newPosition);
        } else {
            escrowPosition.collateral += ((postBalance - prvBalance) * 1e12);
            _newPosition = escrowPosition;
            IVaultFacet(diamond).updatePositionForLiquidator(_key, _newKey, _newPosition);
        }

        liquidablePositionsCount = liquidablePositionsCount - 1;
        delete keyToLiquidablePosition[_key];
        delete keyToLiquidablePositionDetails[_key];

        emit TransferPositionEscrowToLiquidator(
            _newKey,
            _contractAddress,
            msg.sender,
            _newPosition.indexToken,
            _newPosition.isLong,
            _newPosition.size,
            _newPosition.collateral,
            _newPosition.averagePrice,
            _newPosition.reserveAmount,
            _newPosition.viaOrder,
            block.timestamp
        );
    }

    // ========================== Public Functions ========================== //

    /**
     * @dev Initializes the contract with initial parameters. Should be called only once.
     * @param _usdc The address of the USDC token contract.
     */
    function initialize(address _usdc) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        usdc = _usdc;
    }

    // ========================== Internal Functions ========================== //

    /**
     * @dev Checks authorization for contract upgrades.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    // ========================== Private Functions ========================== //

    // ========================== View and Pure Functions ========================== //

    /**
     * @notice Retrieves length of liquidable positions array.
     * @param _key The key of the position.
     * @return The collateral requiremnt and liquidable position with respect to key
     */
    function getLiquidablePositionByKey(bytes32 _key) public view returns (uint256, Position memory) {
        return (keyToLiquidablePositionDetails[_key].collateralForLiquidation, keyToLiquidablePosition[_key]);
    }

    /**
     * @dev Generates a unique position key based on account, token, and long/short status.
     * @param _account The account address.
     * @param _previousAccount The previous account address.
     * @param _indexToken The token address.
     * @param _isLong Boolean indicating if the position is long.
     * @return posKey The unique position key.
     */
    function getPositionKey(address _account, address _previousAccount, address _indexToken, bool _isLong)
        private
        pure
        returns (bytes32 posKey)
    {
        return keccak256(abi.encodePacked(_account, _previousAccount, _indexToken, _isLong));
    }

}
