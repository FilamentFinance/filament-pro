// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import {
    BASIS_POINTS_DIVISOR,
    Compartment,
    INTEREST_RATE_DECIMALS,
    InterestRateParameters,
    Position,
    Stake,
    UnstakeRequest
} from "../interfaces/ICommon.sol";

import { AppStorage } from "../AppStorage.sol";
import { IDeposit } from "../interfaces/IDeposit.sol";
import { IKeeper } from "../interfaces/IKeeper.sol";
import { IVaultFacet } from "../interfaces/IVaultFacet.sol";
import { IViewFacet } from "../interfaces/IViewFacet.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title VaultFacet
/// @dev This contract manages the state of the protocol, including rebalancing, ADL, global PNL, and LP balances.
/// @notice The contract supports functionalities for governance actions, LP token management, and protocol parameters
/// @notice adjustments.
/// @author Filament Finance
contract VaultFacet is IVaultFacet, PausableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    AppStorage internal s;

    // ========================== Errors ========================== //
    error VaultFacet__InvalidRouter();
    error VaultFacet__InvalidEscrow();
    error VaultFacet__OnlyRouterEscrow();
    error VaultFacet__InvalidAddress();
    error VaultFacet__AssetAlreadyExists();
    error VaultFacet__InvalidEpoch();
    error VaultFacet__InvalidOptimalUtilization();
    error VaultFacet__InvalidADLPercentage();
    error VaultFacet__ArrayLengthsMismatch();
    error VaultFacet__PercentageMismatch();
    error VaultFacet__ZeroAmount();
    error VaultFacet__RequestExceedsBalance();
    error VaultFacet__RequestExceedsClaim();
    error VaultFacet__InsufficientAmount();
    error VaultFacet__CombPoolLimitExceeded();
    error VaultFacet__UnlistedAsset();
    error VaultFacet__RequestExceedsMaxWithdrawable();

    // ========================== Events ========================== //
    event Staked(address staker, uint256 amount);
    event NewAssetAdded(address[] assetAddress, uint256[] percentage);
    event EpochDurationUpdated(uint256 time);
    event LiquidationLeverageUpdated(address asset, uint256 newValue);
    event IndexTokenAdded(address tokenAddress);
    event EscrowAddressAdded(address escrow);
    event ProtocolLiquidatorAdded(address protocolLiquidator);
    event LpTokenAddressAdded(address lpToken);
    event KeeperAddressAdded(address deposit);
    event DepositAddressAdded(address deposit);
    event USDCAddressAdded(address usdc);
    event Unstaked(address staker, uint256 amount);
    event SequencerAdded(address[] sequencer);
    event SequencerRemoved(address sequencer);
    event LiquidityRemoved(address account, uint256 amount);
    event LiquidityReduced(uint256 amount);
    event TransferOut(address token, uint256 amount, address receiver);
    event LiquidityAdded(address account, uint256 amount);
    event MaxLeverageUpdated(uint256 maxLeverage);
    event TransferIn(address token, uint256 amount);
    event AddedToCompartment(uint256 amount);
    event CombPoolLimitUpdated(uint256 newLimit);
    event InterestRateParametersUpdated(address indexToken, uint256 Bs, uint256 S1, uint256 S2, uint256 Uo);
    event PositionKey(bytes32 indexed posKey, address indexed account, address indexed indexToken,  bool isLong);

    // ========================== Modifiers ========================== //
    /// @notice Modifier to restrict function access to only the router address
    /// @dev Reverts with VaultFacet__InvalidRouter if caller is not the router
    modifier onlyRouter() {
        require(s.router == msg.sender, VaultFacet__InvalidRouter());
        _;
    }

    /// @notice Modifier to restrict function access to only the escrow address
    /// @dev Reverts with VaultFacet__InvalidEscrow if caller is not the escrow
    modifier onlyEscrow() {
        require(msg.sender == s.escrow, VaultFacet__InvalidEscrow());
        _;
    }

    /// @notice Modifier to restrict function access to only the contract owner
    /// @dev Uses LibDiamond's enforceIsContractOwner function for ownership check
    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    /// @notice Modifier to restrict function access to either router or escrow addresses
    /// @dev Reverts with VaultFacet__OnlyRouterEscrow if caller is neither router nor escrow
    modifier onlyRouterEscrow() {
        require(s.router == msg.sender || s.escrow == msg.sender, VaultFacet__OnlyRouterEscrow());
        _;
    }

    // ========================== Functions ========================== //

    // ========================== External Functions ========================== //

    /// @notice Pauses the contract, preventing certain actions from being executed
    /// @dev Can only be called by the contract owner (governance)
    function pause() external payable onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, allowing paused actions to resume
    /// @dev Can only be called by the contract owner (governance)
    function unpause() external payable onlyOwner {
        _unpause();
    }
    // @audit - PVE008 - For onlyOwner modifier, we will be using multisig wallet.

    /// @notice Adds sequencer addresses to the protocol
    /// @dev Can only be called by the contract owner (governance)
    /// @param _addresses Array of sequencer addresses to add
    function addSequencer(address[] memory _addresses) external payable onlyOwner {
        for (uint256 i = 0; i < _addresses.length;) {
            s.isSequencer[_addresses[i]] = true;
            unchecked {
                ++i;
            }
        }
        emit SequencerAdded(_addresses);
    }

    /// @notice Removes a sequencer address from the protocol
    /// @dev Can only be called by the contract owner (governance)
    /// @param _address The sequencer address to remove
    function removeSequencer(address _address) external payable onlyOwner {
        delete s.isSequencer[_address];
        emit SequencerRemoved(_address);
    }

    /// @notice Adds or updates the router address
    /// @dev Can only be called by the contract owner (governance)
    /// @param router The new router address to set
    function addRouter(address router) external payable onlyOwner {
        if (s.router != router) {
            s.router = router;
        }
    }

    /// @notice Updates the minimum dust size threshold
    /// @dev Can only be called by the contract owner (governance)
    /// @param _dustSize The new dust size value to set
    function updateDustSize(uint256 _dustSize) external payable onlyOwner {
        s.dustSize = _dustSize;
    }

    /// @notice Updates the maximum leverage a liquidator can use to acquire a position
    /// @dev Can only be called by the contract owner (governance)
    /// @param _value The new maximum leverage value
    function updateMaxLiquidatorLeverageToAcquirePosition(uint256 _value) external payable onlyOwner {
        s.maxLiquidatorLeverageToAcquirePosition = _value;
    }

    /// @notice Adds a new index token address to the protocol
    /// @dev Can only be called by the contract owner (governance)
    /// @param _address The address of the new index token to be added
    function addIndexToken(address _address) external payable onlyOwner {
        require(_address != address(0), VaultFacet__InvalidAddress());
        require(s.isIndexToken[_address] == false, VaultFacet__AssetAlreadyExists());
        s.allIndexTokens.push(_address);
        s.isIndexToken[_address] = true;
        emit IndexTokenAdded(_address);
    }

    /// @notice Updates the epoch duration for the protocol
    /// @dev Can only be called by the contract owner (governance)
    /// @param timeInHours The new epoch duration in hours
    function updateEpochDuration(uint256 timeInHours) external payable onlyOwner {
        require(timeInHours != 0, VaultFacet__InvalidEpoch());
        s.epochDuration = timeInHours;
        emit EpochDurationUpdated(timeInHours);
    }

    /// @notice Adds compartmentalization time for a specific asset
    /// @dev Can only be called by the contract owner (governance)
    /// @param timeInSeconds The compartmentalization time in seconds
    function addCompartmentalizationTime(uint256 timeInSeconds) external payable onlyOwner {
        s.compartmentalizationTime = timeInSeconds;
    }

    /// @notice Adds optimal utilization percentage for a specific index token
    /// @dev Can only be called by the contract owner (governance)
    /// @param _percentage The optimal utilization percentage
    /// @param _indexToken The address of the index token
    function addOptimalUtilization(uint256 _percentage, address _indexToken) external payable onlyOwner {
        require(_percentage < BASIS_POINTS_DIVISOR, VaultFacet__InvalidOptimalUtilization()); // #Zokyo-45
        s.optimalUtilization[_indexToken] = _percentage;
    }

    /// @notice Sets the ADL percentage for a specific asset
    /// @dev Can only be called by the contract owner (governance)
    /// @param _asset The address of the asset
    /// @param _percentage The ADL percentage to set
    function setADLPercentage(address _asset, uint256 _percentage) external payable onlyOwner {
        require(_percentage < BASIS_POINTS_DIVISOR, VaultFacet__InvalidADLPercentage());
        s.adlPercentage[_asset] = _percentage;
    }

    /// @notice Updates the collateralization ratio for a specific asset
    /// @dev Can only be called by the contract owner (governance)
    /// @param _address The address of the asset
    /// @param _value The new collateralization ratio value
    function updateLiquidationLeverage(address _address, uint256 _value) external payable onlyOwner {
        s.liquidationLeverage[_address] = _value;
        s.lastLiquidationLeverageUpdate[_address] = block.timestamp;
        emit LiquidationLeverageUpdated(_address, _value);
    }

    /// @notice Updates the new position for the liquidator
    /// @param _escrowKey The escrow key
    /// @param _newKey The position key
    /// @param _newPosition The new position
    function updatePositionForLiquidator(bytes32 _escrowKey, bytes32 _newKey, Position memory _newPosition)
        external
        onlyEscrow
    {
        delete s.positions[_escrowKey];
        s.positions[_newKey] = _newPosition;
    }

    /// @notice Adds an escrow contract address for managing protocol funds
    /// @dev Can only be called by the contract owner (governance)
    /// @param _escrow The address of the escrow contract
    function addEscrow(address _escrow) external payable onlyOwner {
        if (s.escrow != _escrow) {
            s.escrow = _escrow;
            emit EscrowAddressAdded(_escrow);
        }
    }

    /// @notice Adds a protocol liquidator address for handling liquidations
    /// @dev Can only be called by the contract owner (governance)
    /// @param _protocolLiquidator The address of the protocol liquidator
    function addProtocolLiquidator(address _protocolLiquidator) external payable onlyOwner {
        if (!s.isProtocolLiquidator[_protocolLiquidator]) {
            s.isProtocolLiquidator[_protocolLiquidator] = true;
            emit ProtocolLiquidatorAdded(_protocolLiquidator);
        }
    }

    /// @notice Adds a Lp token contract address for managing LP tokens
    /// @dev Can only be called by the contract owner (governance)
    /// @param _lpTokenAddress The address of the LpToken
    function addLpTokenContract(address _lpTokenAddress) external payable onlyOwner {
        s.lpToken = _lpTokenAddress;
        emit LpTokenAddressAdded(_lpTokenAddress);
    }

    /// @notice Adds a keeper contract address
    /// @dev Can only be called by the contract owner (governance)
    /// @param _keeperAddress The address of the keeper contract
    function addKeeperContract(address _keeperAddress) external payable onlyOwner {
        s.keeper = _keeperAddress;
        emit KeeperAddressAdded(_keeperAddress);
    }

    /// @notice Adds a deposit contract address
    /// @dev Can only be called by the contract owner (governance)
    /// @param _depositAddress The address of the deposit contract
    function addDepositContract(address _depositAddress) external payable onlyOwner {
        s.deposit = _depositAddress;
        emit DepositAddressAdded(_depositAddress);
    }

    /// @notice Sets the USDC contract address
    /// @dev Can only be called by the contract owner (governance)
    /// @param _usdcAddress The address of the USDC contract
    function setUSDCContract(address _usdcAddress) external payable onlyOwner {
        s.usdc = _usdcAddress;
        emit USDCAddressAdded(_usdcAddress);
    }

    /// @notice Sets max Leverage for Positions while removing collateral
    /// @dev Can only be called by the contract owner (governance)
    /// @param _newMaxLeverage The new max leverage value
    function setMaxLeverage(uint256 _newMaxLeverage) external payable onlyOwner {
        s.maxLeverage = _newMaxLeverage;
        emit MaxLeverageUpdated(_newMaxLeverage);
    }

    /// @notice Update Comb Pool Limit
    /// @dev Can only be called by the contract owner
    /// @param _newLimit New Comb Pool Limit Value
    function updateCombPoolLimit(uint256 _newLimit) external payable onlyOwner {
        if (s.combPoolLimit != _newLimit) {
            s.combPoolLimit = _newLimit;
            emit CombPoolLimitUpdated(_newLimit);
        }
    }

    /// @notice Adds new assets to the protocol and assigns compartment percentages to them
    /// @dev Can only be called by the contract owner (governance)
    /// @param _address An array of new asset addresses to add
    /// @param _percentage An array of compartment percentages corresponding to each asset
    function addNewAsset(address[] calldata _address, uint256[] calldata _percentage) external payable onlyOwner {
        require(_address.length == _percentage.length, VaultFacet__ArrayLengthsMismatch());
        uint256 totalPercent;
        for (uint256 i = 0; i < _percentage.length;) {
            totalPercent = totalPercent + _percentage[i];
            unchecked {
                ++i;
            }
        }
        require(totalPercent == BASIS_POINTS_DIVISOR, VaultFacet__PercentageMismatch());

        for (uint256 i = 0; i < s.allIndexTokens.length;) {
            s.isIndexToken[s.allIndexTokens[i]] = false;
            unchecked {
                ++i;
            }
        }
        delete s.allIndexTokens;

        uint256 length = _address.length;
        for (uint256 i = 0; i < length;) {
            // @audit - N2 - We have made the all mappings to false in line - 284 (So no need to check again here)
            s.allIndexTokens.push(_address[i]);
            s.isIndexToken[_address[i]] = true;
            s.compartments[_address[i]].assignedPercentage = _percentage[i]; // #Zokyo-64
            unchecked {
                ++i;
            }
        }
        emit NewAssetAdded(_address, _percentage);
    }

    /// @notice Allows users to stake their LP tokens in the Vault
    /// @dev Requires that the amount to be staked is greater than 0
    /// @param _amount The amount of LP tokens to stake
    function stakeLP(uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount != 0, VaultFacet__ZeroAmount());
        uint256 dnAmount = _amount / 10 ** 12;
        IERC20(s.lpToken).safeTransferFrom(msg.sender, address(this), dnAmount);
        s.stakes[msg.sender].stakedAmount = s.stakes[msg.sender].stakedAmount + _amount;
        s.totalFLPStaked = s.totalFLPStaked + _amount;
        emit Staked(msg.sender, _amount);
    }

    /// @notice Allows users to unstake their LP tokens after the unstake period has passed
    /// @dev Requires that the user has a stake greater than or equal to the amount to unstake
    /// @param _amount The amount of LP tokens to unstake
    function unstakeLP(uint256 _amount) external nonReentrant whenNotPaused {
        Stake memory st = s.stakes[msg.sender];
        require(st.stakedAmount >= _amount, VaultFacet__RequestExceedsBalance());

        // Update staked amounts
        st.unstakedRequested = st.unstakedRequested + _amount;
        st.stakedAmount = st.stakedAmount - _amount;
        s.stakes[msg.sender] = st;
        s.totalFLPStaked -= _amount;

        // All requests made the within 24hours it is counted the same
        uint256 today = block.timestamp; // 0 , 25
        uint256 allUnstakeRequests = s.unstakeRequests[msg.sender].length; //  1
        bool sameDay = false;
        uint256 lastUnstakeDay;
        if (allUnstakeRequests != 0) {
            lastUnstakeDay = s.unstakeRequests[msg.sender][allUnstakeRequests - 1].requestDay; // 0
            if (today < lastUnstakeDay + 24 hours) {
                sameDay = true;
            }
        }

        // Check if unstaking the same day again, or new request
        if (sameDay) {
            UnstakeRequest storage lastUnstakeReq = s.unstakeRequests[msg.sender][allUnstakeRequests - 1];
            lastUnstakeReq.amount = lastUnstakeReq.amount + _amount;
        } else {
            UnstakeRequest memory unReq = UnstakeRequest({ amount: _amount, requestDay: today });
            s.unstakeRequests[msg.sender].push(unReq);
        }
        emit Unstaked(msg.sender, _amount);
    }

    /// @notice Allows a user to claim a specified amount of tokens from their stake
    /// @param _amount The amount of tokens to claim
    /// @dev Requirements:
    /// @dev - User must have enough unstaked tokens available to claim (_amount)
    /// @dev - Claimable amount must be released and available
    /// @dev Effects:
    /// @dev - Updates the claimed amount for the user's stake
    /// @dev - Transfers the claimed tokens to the user
    function claim(uint256 _amount) external nonReentrant {
        Stake memory st = s.stakes[msg.sender];
        require(st.unstakedRequested >= _amount + st.unstakeClaimed, VaultFacet__RequestExceedsBalance());
        uint256 claimableAmount = IViewFacet(address(this)).getClaimableAmount(msg.sender);
        require(claimableAmount >= _amount, VaultFacet__RequestExceedsClaim());
        st.unstakeClaimed += _amount;
        s.stakes[msg.sender] = st;
        uint256 dnAmount = _amount / 10 ** 12;
        IERC20(s.lpToken).safeTransfer(msg.sender, dnAmount);
    }

    /// @notice Compartmentalizes assets based on current balances and assigned percentages
    /// @dev This function checks for imbalance in the system and rebalances assets accordingly
    /// @dev Effects:
    /// @dev - Updates valid and invalid assets arrays based on current balances
    /// @dev - Calculates excess and required funds for assets and adjusts balances accordingly
    function compartmentalize() external {
        updateValidAndInvalidCompartment();
        uint256 rebalancingTime = s.compartmentalizationTime;
        uint256 intervalInHours;
        uint256 totalAvailableAssets;
        uint256 totalRequiredAssets;
        uint256 lengthValidAssets = s.validAssets.length;
        uint256 lengthInvalidAssets = s.invalidAssets.length;
        if ((block.timestamp < s.lastCompartmentalizationTime + rebalancingTime)) {
            return;
        } else {
            intervalInHours = (block.timestamp - s.lastCompartmentalizationTime) / 3600;
        }
        s.epochInterval = s.epochInterval + intervalInHours;
        if (s.epochInterval >= s.epochDuration) {
            s.epochInterval = 0;
        }

        uint256 epochDurationInHours = s.epochDuration - s.epochInterval;
        if (validateCompartmentNeutrality()) {
            return;
        }

        /// @notice It initializes a variable TotalAvailableAssets to sum up all excess funds
        //from  s.validAssets, which are assets currently within the expected balance range.
        /// @dev It iterates over validAssets to calculate extraUSDC, the excess funds for each asset.
        // It also updates compartmentBal, lastAvailable, and lastTransferUSDC based on the condition whether
        //the last available excess is equal to the current one.
        //The total excess funds are accumulated into TotalAvailableAssets.

        for (uint256 i = 0; i < lengthValidAssets;) {
            address _asset = s.validAssets[i];
            if (s.epochInterval == 0) {
                delete s.lastAvailable[_asset];
                delete s.lastTransferUSDC[_asset];
            }
            Compartment memory compartment = s.compartments[_asset]; // ETH Compartments
            uint256 extraUSDC =
                compartment.balance - (s.usdBalance * compartment.assignedPercentage) / (BASIS_POINTS_DIVISOR);
            if (s.lastAvailable[_asset] == extraUSDC) {
                if (isBorrowLimitHit(_asset, compartment.balance, s.lastTransferUSDC[_asset])) {
                    return;
                }
                compartment.balance = compartment.balance - s.lastTransferUSDC[_asset];
                s.lastAvailable[_asset] = s.lastAvailable[_asset] - s.lastTransferUSDC[_asset];
                s.compartments[_asset] = compartment;
            } else {
                s.lastTransferUSDC[_asset] = extraUSDC / epochDurationInHours;
                s.lastAvailable[_asset] = extraUSDC - s.lastTransferUSDC[_asset];
                if (isBorrowLimitHit(_asset, compartment.balance, s.lastTransferUSDC[_asset])) {
                    return;
                }
                compartment.balance = compartment.balance - s.lastTransferUSDC[_asset];
                s.compartments[_asset] = compartment;
            }
            totalAvailableAssets = totalAvailableAssets + extraUSDC;
            unchecked {
                ++i;
            }
        }

        /// @notice It initializes a variable TotalRequiredAssets to sum up all funds needed by invalidAssets,
        //which are assets currently below the expected balance range.
        /// @dev It then iterates over invalidAssets to calculate the required funds to rebalance each asset and updates
        /// compartmentBal,
        // lastRequirement, and lastTransferUSDC accordingly.
        //The required funds are subtracted from TotalRequiredAssets as they are allocated to each asset.
        for (uint256 i = 0; i < lengthInvalidAssets;) {
            address _asset = s.invalidAssets[i];
            if (s.epochInterval == 0) {
                delete s.lastRequirement[_asset];
                delete s.lastTransferUSDC[_asset];
            }
            Compartment memory compartment = s.compartments[_asset];
            uint256 desiredBal = (s.usdBalance * compartment.assignedPercentage) / (BASIS_POINTS_DIVISOR);
            uint256 requiredAmount = (desiredBal - compartment.balance);
            totalRequiredAssets = totalRequiredAssets + requiredAmount;

            if (s.lastRequirement[_asset] >= requiredAmount && requiredAmount <= s.lastTransferUSDC[_asset]) {
                compartment.balance = compartment.balance + requiredAmount;
                compartment.isValid = true;
                s.lastRequirement[_asset] = 0;
                totalRequiredAssets = totalRequiredAssets - requiredAmount;
                s.compartments[_asset] = compartment;
            } else if (s.lastRequirement[_asset] >= requiredAmount && requiredAmount > s.lastTransferUSDC[_asset]) {
                compartment.balance = compartment.balance + s.lastTransferUSDC[_asset];
                s.lastRequirement[_asset] = requiredAmount - s.lastTransferUSDC[_asset];
                totalRequiredAssets = totalRequiredAssets - s.lastTransferUSDC[_asset];
                s.compartments[_asset] = compartment;
            } else if (s.lastRequirement[_asset] < requiredAmount) {
                s.lastTransferUSDC[_asset] = (requiredAmount / epochDurationInHours); // Precison Loss Rectifier
                compartment.balance = compartment.balance + s.lastTransferUSDC[_asset];
                s.lastRequirement[_asset] = requiredAmount - s.lastTransferUSDC[_asset];
                totalRequiredAssets = totalRequiredAssets - s.lastTransferUSDC[_asset];
                s.compartments[_asset] = compartment;
            }
            unchecked {
                ++i;
            }
        }

        s.lastCompartmentalizationTime = block.timestamp;
        return;
    }

    /// @notice This function allows users to remove their collateral from the Vault
    /// @dev It validates the amount, converts LP tokens back to USD, burns the LP tokens from the sender's balance,
    /// transfers out the USD to the sender, updates the compartment balances, and
    /// emits an event to record the liquidity removal
    /// @param _flpAmount The amount of LP tokens to remove
    function removeLiquidity(uint256 _flpAmount) external nonReentrant {
        require(_flpAmount != 0, VaultFacet__ZeroAmount());
        uint256 assetsToWithdraw = IERC4626(s.lpToken).previewRedeem(_flpAmount); // 6 decimals
        uint256 usdAmount = assetsToWithdraw * 1e12;
        uint256 maxWithdrawableUSDC = _maxWithdrawableAmount();
        require(usdAmount <= maxWithdrawableUSDC, VaultFacet__RequestExceedsMaxWithdrawable());
        IERC4626(s.lpToken).redeem(_flpAmount, msg.sender, msg.sender); // 6 decimals
        _transferOut(usdAmount, msg.sender); // 12 decimals
        updateCompartmentsReduceLiq(usdAmount);
        emit LiquidityRemoved(msg.sender, usdAmount);
    }

    /// @notice Redeems LP tokens for USDC, transferring the corresponding amount to the caller
    /// @dev This function first updates all balances, redeems the specified `_shares` of LP tokens,
    /// transfers the redeemed USDC to the caller, and updates the compartments after reducing liquidity
    /// @param _shares The number of LP tokens (shares) to redeem
    function redeemLPTokens(uint256 _shares) external nonReentrant {
        require(_shares != 0, VaultFacet__ZeroAmount());
        uint256 usdAmount = IERC4626(s.lpToken).redeem(_shares, msg.sender, msg.sender);
        _transferOut(usdAmount * 10 ** 12, msg.sender);
        updateCompartmentsReduceLiq(usdAmount);
    }

    /// @notice Update collateral and position details after liquidation
    /// @dev Only callable by the escrow contract
    /// @param _position Position object containing updated details
    /// @param _key Key of the position in the positions mapping
    function updateCollateralFromLiquidation(Position memory _position, bytes32 _key) external onlyEscrow {
        s.positions[_key] = _position;
    }

    // ========================== Public Functions ========================== //

    /// @notice The function is designed to allow users to add liquidity in the form of USD to the Vault
    /// @dev It performs validation checks, mints LP tokens in exchange for the USD, updates compartment balances,
    /// and emits an event to record the liquidity addition
    /// @param _amount The amount of USD to add as liquidity
    function addLiquidity(uint256 _amount) external nonReentrant {
        require(s.usdBalance + _amount <= s.combPoolLimit, VaultFacet__CombPoolLimitExceeded());
        require(_amount != 0, VaultFacet__ZeroAmount());
        require(_amount == _transferInLiquidity(_amount, msg.sender), VaultFacet__InsufficientAmount());

        uint256 dnAmount = _amount / 10 ** 12;
        IERC4626(s.lpToken).deposit(dnAmount, msg.sender);
        updateCompartmentsAddLiq(_amount);
        emit LiquidityAdded(msg.sender, _amount);
    }

    // ========================== Internal Functions ========================== //

    /// @notice Updates and retrieves arrays of valid and invalid assets based on current compartment balances
    /// @dev Checks each asset's balance against its assigned percentage of USDBalance
    /// @dev Effects:
    /// @dev - Updates s.validAssets and s.invalidAssets arrays based on compartment balances
    /// @return The arrays of valid and invalid assets
    function updateValidAndInvalidCompartment() internal returns (address[] memory, address[] memory) {
        delete s.validAssets;
        delete s.invalidAssets;
        uint256 length = s.allIndexTokens.length;
        for (uint256 i = 0; i < length;) {
            address asset = s.allIndexTokens[i];
            Compartment memory compartment = s.compartments[asset];

            if (compartment.balance < (s.usdBalance * (compartment.assignedPercentage)) / (BASIS_POINTS_DIVISOR)) {
                s.invalidAssets.push(asset);
                compartment.isValid = false;
                s.compartments[asset] = compartment;
            } else {
                s.validAssets.push(asset);
                compartment.isValid = true;
                s.compartments[asset] = compartment;
            }
            unchecked {
                ++i;
            }
        }

        return (s.invalidAssets, s.validAssets);
    }

    /// @notice This is an internal function that reduces liquidity from each asset's balance proportionally
    /// @dev Iterates through s.allIndexTokens and reduces the compartmentBal[asset] based on the
    /// assignedCompartments[asset]
    /// @param amount The amount of liquidity to reduce
    function updateCompartmentsReduceLiq(uint256 amount) internal {
        uint256 length = s.allIndexTokens.length;
        for (uint256 i = 0; i < length;) {
            address asset = s.allIndexTokens[i];
            Compartment memory compartment = s.compartments[asset];
            uint256 liquidityPerAsset = (amount * (compartment.assignedPercentage)) / (BASIS_POINTS_DIVISOR);
            compartment.balance = compartment.balance - liquidityPerAsset;
            s.compartments[asset] = compartment;
            unchecked {
                ++i;
            }
        }

        s.usdBalance = s.usdBalance - amount;
        emit LiquidityReduced(amount);
    }

    /// @notice Transfers out an ERC20 token from the Vault to a receiver's address
    /// @dev Performs the transfer and updates the Vault's USD balance accordingly
    /// @param _amount The amount to transfer
    /// @param _receiver The address to receive the tokens
    function _transferOut(uint256 _amount, address _receiver) internal {
        uint256 dnAmount = _amount / 10 ** 12;
        uint256 prvBalance = IERC20(s.usdc).balanceOf(s.deposit);
        IERC20(s.usdc).safeTransfer(s.deposit, dnAmount);
        uint256 postBalance = IERC20(s.usdc).balanceOf(s.deposit); // deposit contract could recieve less
        _amount = (postBalance - prvBalance) * 10 ** 12;
        IDeposit(s.deposit).transferIn(_receiver, _amount);
        emit TransferOut(s.usdc, _amount, _receiver);
    }

    /// @notice Transfers in liquidity from a sender to the Vault
    /// @dev Handles the transfer of tokens and emits a TransferIn event
    /// @param amount The amount of tokens to transfer in
    /// @param sender The address sending the tokens
    /// @return The amount of tokens transferred
    function _transferInLiquidity(uint256 amount, address sender) internal returns (uint256) {
        IDeposit(s.deposit).transferOutLiquidity(sender, amount);
        emit TransferIn(s.usdc, amount);
        return amount;
    }

    /// @notice Distributes liquidity across different assets based on their assigned compartment values
    /// @dev For each asset in allIndexTokens, calculates and adds liquidity to each compartment
    /// @param amount The amount of liquidity to distribute
    function updateCompartmentsAddLiq(uint256 amount) internal {
        uint256 length = s.allIndexTokens.length;
        for (uint256 i = 0; i < length;) {
            address asset = s.allIndexTokens[i];
            Compartment memory compartment = s.compartments[asset];
            uint256 liquidityPerAsset = ((amount * (compartment.assignedPercentage)) / (BASIS_POINTS_DIVISOR));
            compartment.balance = compartment.balance + liquidityPerAsset;
            s.compartments[asset] = compartment;
            unchecked {
                ++i;
            }
        }

        s.usdBalance = s.usdBalance + amount;
        emit AddedToCompartment(amount);
    }

    /// @notice Internal function to calculate the maximum withdrawable amount from the pool.
    /// @dev Iterates through all indexed tokens to compute the lowest percentage of assets that can be withdrawn,
    ///      based on compartment balances and optimal utilization rates.
    /// @return The maximum withdrawable amount in USDC value.
    function _maxWithdrawableAmount() internal view returns (uint256) {
        uint256 length = s.allIndexTokens.length;
        uint256 lowestPerc = type(uint256).max; // Initialize to maximum value for comparison
        uint256 decimal_precision = 1e18; // Precision factor for percentage calculations

        for (uint256 i = 0; i < length; i++) {
            address asset = s.allIndexTokens[i];
            Compartment memory compartment = s.compartments[asset];

            // Calculate the maximum amount available for withdrawal
            uint256 maxAvailable = (
                ((compartment.balance + s.borrowedAmountFromPool[asset].total) * s.optimalUtilization[asset])
                    / BASIS_POINTS_DIVISOR
            ) - s.borrowedAmountFromPool[asset].total;

            // Calculate the percentage of the asset that can be withdrawn
            uint256 percAssetCanBeTakenOut =
                (maxAvailable * decimal_precision) / (compartment.balance + s.borrowedAmountFromPool[asset].total);

            // Update the lowest percentage if the current value is smaller
            if (percAssetCanBeTakenOut < lowestPerc) {
                lowestPerc = percAssetCanBeTakenOut;
            }
        }

        // Convert the lowest percentage into a USDC value
        uint256 usdcValue = lowestPerc * (s.usdBalance + s.totalBorrowedUSD) / decimal_precision;
        return usdcValue;
    }
    // ========================== Private Functions ========================== //
    // ========================== View and Pure Functions ========================== //

    /// @notice Checks if a borrowing limit is hit after deducting a specified amount from the compartment balance.
    /// @param _indexToken The address of the asset to check.
    /// @param _compBalance The current balance of the compartment for the asset.
    /// @param _deductAmount The amount deducted from the compartment balance.
    /// @return True if the borrowing limit is hit, otherwise false.
    /// @dev Compares the balance after deduction with the borrowing limit based on optimal utilization.
    function isBorrowLimitHit(address _indexToken, uint256 _compBalance, uint256 _deductAmount)
        internal
        view
        returns (bool)
    {
        uint256 balAfterDeduct = _compBalance - _deductAmount;
        if (balAfterDeduct <= (_compBalance * s.optimalUtilization[_indexToken]) / BASIS_POINTS_DIVISOR) {
            return true;
        }
        return false;
    }

    /// @notice Checks if all compartment balances match their expected values based on assigned percentages.
    /// @dev Compares each asset's compartment balance with the expected balance calculated from assigned percentage and
    /// USDBalance.
    /// @return True if all compartment balances are in neutrality, otherwise false.
    function validateCompartmentNeutrality() internal view returns (bool) {
        uint256 length = s.allIndexTokens.length;
        for (uint256 i = 0; i < length;) {
            address asset = s.allIndexTokens[i];
            Compartment memory compartment = s.compartments[asset];
            if (compartment.balance != (compartment.assignedPercentage * s.usdBalance) / (BASIS_POINTS_DIVISOR)) {
                return false;
            }
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @notice Validates the interest rate parameters for a given token.
    /// @param _interestRateParameters The interest rate parameters to validate.
    /// @dev Ensures that the token is listed and Uo is within a valid range.
    function validateInterestRateParams(InterestRateParameters calldata _interestRateParameters) internal view {
        // #Zokyo-54
        require(
            IViewFacet(address(this)).isValidIndexToken(_interestRateParameters.indexToken), VaultFacet__UnlistedAsset()
        );
        // @audit - PVE003-2 - U0 is set as 8000 (80%), which should be less than 10000 (100%) - Don't include in audit
        // report
        require(_interestRateParameters.Uo <= 10_000, VaultFacet__InvalidOptimalUtilization());
    }

    /// @notice Calculates the borrow rate based on the utilization and token parameters.
    /// @param _utilisation The current utilization of the token.
    /// @param _indexToken The token address for which to calculate the borrow rate.
    /// @return borrowRate The calculated borrow rate with 6 decimals.
    function calculateBorrowRate(uint256 _utilisation, address _indexToken)
        internal
        view
        returns (uint256 borrowRate)
    {
        InterestRateParameters memory params = s.interestRateParameters[_indexToken];

        if (_utilisation <= params.Uo) {
            borrowRate = params.Bs + ((_utilisation * params.S1) / 1e2);
        } else {
            borrowRate = params.Bs + ((params.Uo * params.S1 / 1e2) + ((_utilisation - params.Uo) * params.S2) / 1e2);
        }
    }

    /// @notice Retrieves the borrow rate and utilization for a given token.
    /// @param _indexToken The token address for which to retrieve the rates.
    /// @return borrowRate The current borrow rate with 6 decimals.
    /// @return utilization The current utilization with 4 decimals (0 to 10000).
    function getBorrowRate(address _indexToken) public view returns (uint256 borrowRate, uint256 utilization) {
        (uint256 totalBalance,,) = IViewFacet(address(this)).compartments(_indexToken);
        // decimals 10^6

        if (totalBalance == 0) {
            uint256 baseRate = calculateBorrowRate(0, _indexToken);
            return (baseRate, 0);
        }
        (uint256 totalBorrowedAmount,,) = IViewFacet(address(this)).borrowedAmountFromPool(_indexToken);
        uint256 _optimalUtilization = IViewFacet(address(this)).getOptimalUtilization(_indexToken);
        uint256 denom = _optimalUtilization * (totalBalance + totalBorrowedAmount);
        // @audit - PVE003 - Fixed, We were using * 1e6, so in calculateBorrowRate() we were accounting there (U0 *
        // 1e2), Now, we changed in both places
        // @audit - Don't include in the report
        utilization = (totalBorrowedAmount * BASIS_POINTS_DIVISOR * BASIS_POINTS_DIVISOR) / denom;
        // uint256 utilizationLong = (totalBorrowedLong * 10_000 * 1e6) / denom;
        // uint256 utilizationShort = (totalBorrowedShort * 10_000 * 1e6) / denom;

        borrowRate = calculateBorrowRate(utilization, _indexToken);
        // borrowRateLong = calculateBorrowRate(utilizationLong, _indexToken);
        // borrowRateShort = calculateBorrowRate(utilizationShort, _indexToken);
    }

    /// @notice Computes the maximum amount that can be withdrawn from the pool in USDC value.
    /// @dev This function delegates the computation to the internal `_maxWithdrawableAmount` function.
    /// @return The maximum withdrawable amount in USDC value.
    function maxWithdrawableAmount() external view returns (uint256) {
        return _maxWithdrawableAmount();
    }

    /// @notice Adds interest rate parameters for multiple assets at once.
    /// @param _interestRateParameters Array of interest rate parameters.
    function addInterestRateParams(InterestRateParameters[] calldata _interestRateParameters)
        external
        payable
        onlyOwner
    {
        uint256 length = _interestRateParameters.length;
        for (uint256 i = 0; i < length;) {
            InterestRateParameters calldata params = _interestRateParameters[i];
            validateInterestRateParams(params);
            s.interestRateParameters[params.indexToken] = params;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Updates interest rate parameters for a single asset.
    /// @param _interestRateParameters New interest rate parameters.
    function updateInterestRateParams(InterestRateParameters calldata _interestRateParameters)
        external
        payable
        onlyOwner
    {
        validateInterestRateParams(_interestRateParameters);
        s.interestRateParameters[_interestRateParameters.indexToken] = _interestRateParameters;
        emit InterestRateParametersUpdated(
            _interestRateParameters.indexToken,
            _interestRateParameters.Bs,
            _interestRateParameters.S1,
            _interestRateParameters.S2,
            _interestRateParameters.Uo
        );
    }

    function addExtraCollateral(address indexToken) external onlyOwner {
        // check approval
        require(IERC20(s.usdc).allowance(msg.sender, address(this)) >= 10e6, "VF: LowAllowance");
        // transfer
        IERC20(s.usdc).safeTransferFrom(msg.sender, address(this), 10e6);
        // update collateral for index tokens
        s.shortCollateral[indexToken] += 5e18;
        s.longCollateral[indexToken] += 5e18;
    }

    // ✅ Deployed on Mainnet
    // Ensure all positons are closed on the removed asset before executing this function
    function moveCollateralFromRemovedAsset(address _removedAsset, address _addedAsset) external onlyOwner {
        require(s.isIndexToken[_addedAsset], "VF: InvalidAsset");
        // require(s.isIndexToken[_removedAsset], "VF: InvalidAsset");
        s.shortCollateral[_addedAsset] += s.shortCollateral[_removedAsset];
        s.longCollateral[_addedAsset] += s.longCollateral[_removedAsset];
        s.shortCollateral[_removedAsset] = 0;
        s.longCollateral[_removedAsset] = 0;
    }

    function updateCollateralMappings(address _indexToken, uint256 _shortCollateral, uint256 _longCollateral)
        external
        onlyOwner
    {
        require(s.isIndexToken[_indexToken], "VF: InvalidAsset");
        s.shortCollateral[_indexToken] = _shortCollateral;
        s.longCollateral[_indexToken] = _longCollateral;
    }

    function deletePositionMitigateRisk(
        address _account,
        address _indexToken,
        address _previousAddress,
        bool _isLong,
        uint256 _deductions
    ) external onlyOwner {
        bytes32 key = IViewFacet(address(this)).getPositionKey(_account, _previousAddress, _indexToken, _isLong);
        Position memory position = s.positions[key];
        address indexToken = position.indexToken;
        uint256 collateral = position.collateral;

        if (position.isLong) {
            s.longCollateral[indexToken] -= collateral;
        } else {
            s.shortCollateral[indexToken] -= collateral;
        }

        delete s.positions[key];
        IDeposit(s.deposit).transferIn(_account, collateral - _deductions);
    }

    function deleteDustPosition(bytes32 key) external onlyOwner {
        // Position memory position = s.positions[key];
        // uint256 size = position.size;
        // require(size < 1_000_000, "VF: LargeSizePosition");
        delete s.positions[key];
    }

    function createPosition(
        address _account,
        uint256 _size,
        uint256 _collateral,
        uint256 _averagePrice,
        uint256 _reserveAmount,
        uint256 _viaOrder,
        uint256 _lastIncreasedTime,
        uint256 _creationTime,
        uint256 _tradingFee,
        int256 _realisedPnl,
        address _indexToken,
        bool _isLong
    ) external onlyOwner {
        bytes32 _key = IViewFacet(address(this)).getPositionKey(_account, 0x0000000000000000000000000000000000000000, _indexToken, _isLong);
        Position memory position = Position({
            indexToken: _indexToken,
            size: _size,
            collateral: _collateral,
            averagePrice: _averagePrice,
            reserveAmount: _reserveAmount,
            viaOrder: _viaOrder,
            lastIncreasedTime: _lastIncreasedTime,
            creationTime: _creationTime,
            tradingFee: _tradingFee,
            realisedPnl: _realisedPnl,
            isLong: _isLong
        });
        s.positions[_key] = position;
        emit PositionKey(_key, _account, _indexToken, _isLong);
        if (_isLong) {
            s.longCollateral[_indexToken] += _collateral;
        } else {
            s.shortCollateral[_indexToken] += _collateral;
        }
    }

}
