// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { IDeposit } from "./interfaces/IDeposit.sol";
import { IViewFacet } from "./interfaces/IViewFacet.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Deposit Contract
/// @notice This contract allows users to deposit and withdraw USDC, with functionalities for locking funds for orders.
/// @dev This contract uses OpenZeppelin upgradeable contracts and SafeERC20 for secure token transfers.
contract Deposit is IDeposit, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20Metadata;

    uint256 constant MAX_DECIMALS = 18;
    /// @notice Address of the USDC token contract
    address public usdc;
    /// @notice Address of the diamond contract
    address public diamond;
    /// @notice Mapping of user addresses to their balances
    mapping(address => uint256) public balances;
    mapping(address => WithdrawRequest) public withdrawRequest;

    // ========================== Errors ========================== //

    error Deposit__LockForOrderFailed(address account);
    error Deposit__UnauthorizedSequencer(address account);
    error Deposit__UnauthorizedDiamond(address account);
    error Deposit__InsuffucientBalance(address account);
    error Deposit__InsufficentAmount();
    error Deposit__InCooldownZone();
    error Deposit__WithdrawFlagged();
    error Deposit__AlreadyFlagged();
    error Deposit__NotFlagged();

    // ========================== Events ========================== //

    event DepositUpdated(address sender, uint256 amount);
    event WithdrawRequested(address sender, uint256 amount, uint256 timestamp);
    event WithdrawClaimed(address sender, uint256 amount, uint256 timestamp);
    event DiamondUpdated(address _newDiamondAddr);
    event WithdrawFlagged(address _suspiciousAddress, bool _isSuspicious);

    // ========================== Modifiers ========================== //

    modifier onlySequencer() {
        bool isSequencerWhitelist = IViewFacet(diamond).isSequencerWhitelisted(msg.sender);
        require(isSequencerWhitelist, Deposit__UnauthorizedSequencer(msg.sender));
        _;
    }

    modifier onlyDiamond() {
        require(msg.sender == diamond, Deposit__UnauthorizedDiamond(msg.sender));
        _;
    }

    // ========================== Functions ========================== //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() payable {
        _disableInitializers();
    }

    // ========================== External Functions ========================== //

    /// @notice Pause the contract, disabling certain functions
    /// @dev Can only be called by the owner
    function pause() external payable onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract, enabling certain functions
    /// @dev Can only be called by the owner
    function unpause() external payable onlyOwner {
        _unpause();
    }

    /// @notice Set the diamond contract address
    /// @param _diamond The address of the diamond contract
    function setDiamondContract(address _diamond) external payable onlyOwner {
        if (diamond != _diamond) {
            diamond = _diamond;
            emit DiamondUpdated(_diamond);
        }
    }

    /// @notice Deposit USDC into the contract
    /// @param _amount The amount of USDC to deposit
    function deposit(uint256 _amount) external nonReentrant whenNotPaused {
        address _usdc = usdc;
        address depositAddr = address(this);
        uint256 prvBalance = IERC20Metadata(_usdc).balanceOf(depositAddr);
        uint256 factor = _factor();
        uint256 normalizedAmount = _amount / 10 ** factor;
        IERC20Metadata(_usdc).safeTransferFrom(msg.sender, depositAddr, normalizedAmount);
        uint256 postBalance = IERC20Metadata(_usdc).balanceOf(depositAddr);
        _amount = (postBalance - prvBalance) * 10 ** factor;
        balances[msg.sender] += _amount;
        emit DepositUpdated(msg.sender, _amount);
    }

    /// @notice Withdraw USDC from the contract
    /// @param _amount The amount of USDC to withdraw
    function requestWithdraw(uint256 _amount) external nonReentrant whenNotPaused {
        uint256 userBalance = balances[msg.sender];
        require(userBalance >= _amount, Deposit__InsuffucientBalance(msg.sender));
        uint256 updatedBalance = userBalance - _amount;
        balances[msg.sender] = updatedBalance;
        withdrawRequest[msg.sender].amount += _amount;
        withdrawRequest[msg.sender].cooldownTime = block.timestamp + 10 minutes;
        emit WithdrawRequested(msg.sender, _amount, block.timestamp);
    }

    /**
     * @notice Flags a withdrawal request as suspicious.
     * @param _address The address of the user whose withdrawal is flagged.
     */
    function flagWithdraw(address _address) external onlySequencer {
        require(!withdrawRequest[_address].isSuspicious, Deposit__AlreadyFlagged());
        withdrawRequest[_address].isSuspicious = true;
        emit WithdrawFlagged(_address, true);
    }

    /**
     * @notice Unflags a withdrawal request which was previously considered suspicious.
     * @param _address The address of the user whose withdrawal is flagged.
     */
    function unflagWithdraw(address _address) external onlySequencer {
        require(withdrawRequest[_address].isSuspicious, Deposit__NotFlagged());
        withdrawRequest[_address].isSuspicious = false;
        emit WithdrawFlagged(_address, false);
    }

    /**
     * @notice Claims a withdrawal request after the cooldown period.
     */
    function claimWithdraw() external nonReentrant whenNotPaused {
        WithdrawRequest memory wr = withdrawRequest[msg.sender];
        require(wr.amount > 0, Deposit__InsufficentAmount());
        require(block.timestamp >= wr.cooldownTime, Deposit__InCooldownZone());
        require(!wr.isSuspicious, Deposit__WithdrawFlagged());
        delete withdrawRequest[msg.sender];
        uint256 factor = _factor();
        uint256 normalizedAmount = wr.amount / 10 ** factor;
        IERC20Metadata(usdc).safeTransfer(msg.sender, normalizedAmount);
        emit WithdrawClaimed(msg.sender, wr.amount, block.timestamp);
    }

    /// @notice Lock an amount of USDC for an order
    /// @param _account The address of the user whose funds will be locked
    /// @param _amount The amount of USDC to lock
    /// @dev Can only be called by the diamond contract
    function lockForAnOrder(address _account, uint256 _amount) external onlyDiamond {
        uint256 userBalance = balances[_account];
        require(_amount <= userBalance, Deposit__LockForOrderFailed(_account));
        // depositDetails[_account].locked = depositDetails[_account].locked + _amount;
        balances[_account] = userBalance - _amount;
        uint256 denormalizedAmount = _amount / 10 ** _factor();
        IERC20Metadata(usdc).safeTransfer(diamond, denormalizedAmount);
    }

    /// @notice Transfer an amount of USDC into a user's balance
    /// @param _trader The address of the user
    /// @param amount The amount of USDC to transfer in
    /// @dev Can only be called by the diamond contract
    function transferIn(address _trader, uint256 amount) external onlyDiamond {
        // #Zokyo-29
        balances[_trader] += amount;
        // No Need to unlock funds here as unlocking has taken place in transferOut function
    }

    /// @notice Transfer an amount of USDC out from a user's available balance to the diamond contract
    /// @param _trader The address of the user
    /// @param amount The amount of USDC to transfer out
    /// @dev Can only be called by the diamond contract
    function transferOutLiquidity(address _trader, uint256 amount) external onlyDiamond {
        // #Zokyo-29
        uint256 userBalance = balances[_trader];
        require(userBalance >= amount, Deposit__InsuffucientBalance(_trader));
        balances[_trader] = userBalance - amount;
        uint256 denormalizedAmount = amount / 10 ** _factor();
        IERC20Metadata(usdc).safeTransfer(diamond, denormalizedAmount);
    }

    // ========================== Public Functions ========================== //

    /// @notice Initialize the contract with the USDC token address
    /// @param _usdc The address of the USDC token contract
    function initialize(address _usdc) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        usdc = _usdc;
    }

    // ========================== Internal Functions ========================== //
    function _factor() internal view returns (uint256) {
        return MAX_DECIMALS - IERC20Metadata(usdc).decimals();
    }

    /// @notice Authorize an upgrade to a new implementation
    /// @param newImplementation The address of the new implementation contract
    /// @dev Can only be called by the owner
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    // ========================== Private Functions ========================== //
    // ========================== View and Pure Functions ========================== //

}
