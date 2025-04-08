// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { IViewFacet } from "./interfaces/IViewFacet.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LP Token Contract
 * @dev ERC4626 token implementation with pausable, upgradeable, and ownership functionalities.
 * @notice This contract represents a Filament Liquidity Provider (FLP) token that follows the ERC4626 standard.
 * It includes functionalities for pausing, upgrading, and managing ownership.
 */
contract LpToken is
    ERC4626Upgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{

    address diamondAddress;

    // ========================== Errors ========================== //

    error LpToken__InvalidAddress();
    error LpToken__OnlyDiamond();
    error LpToken__LowFreeLiquidity(address owner, uint256 assets, uint256 lockedAssets);

    // ========================== Events ========================== //

    /**
     * @dev Emitted when the diamond address is set.
     * @param _diamondAddr The address of the diamond contract.
     */
    event SetDiamond(address _diamondAddr);

    // ========================== Modifiers ========================== //

    /**
     * @dev Modifier to allow only the diamond contract to execute the function.
     */
    modifier onlyDiamond() {
        require(msg.sender == diamondAddress, LpToken__OnlyDiamond());
        _;
    }

    // ========================== Functions ========================== //
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() payable {
        _disableInitializers();
    }

    // ========================== External Functions ========================== //

    /**
     * @notice Pauses token transfers. Only callable by the owner.
     */
    function pause() external payable onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses token transfers. Only callable by the owner.
     */
    function unpause() external payable onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the address of the diamond contract. Only callable by the owner.
     * @param _diamondAddress The address of the diamond contract.
     */
    function setDiamondAddress(address _diamondAddress) external payable onlyOwner {
        // #Zokyo-35
        require(_diamondAddress != address(0), LpToken__InvalidAddress());
        if (diamondAddress != _diamondAddress) {
            diamondAddress = _diamondAddress;
            emit SetDiamond(_diamondAddress);
        }
    }

    // ========================== Public Functions ========================== //

    /**
     * @notice Initializes the token contract with ERC20 details and sets the diamond contract address.
     * @param usdc The address of the USDC token contract.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     */
    function initialize(address usdc, string memory _name, string memory _symbol) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC4626_init(IERC20(usdc));
        __ERC20_init(_name, _symbol);
    }

    /**
     * @notice Mints new tokens to a receiver. Only callable by the diamond contract when not paused.
     * @param shares The number of tokens (shares) to mint.
     * @param receiver The address of the receiver.
     * @return The amount of shares minted.
     */
    function mint(uint256 shares, address receiver) public override onlyDiamond whenNotPaused returns (uint256) {
        _mint(receiver, shares);
        return shares;
    }

    /**
     * @notice Deposits assets to mint tokens (shares) for a receiver. Only callable by the diamond contract when not
     * paused.
     * @param assets The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return shares The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        onlyDiamond
        whenNotPaused
        returns (uint256 shares)
    {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /**
     * @notice Withdraws assets by burning tokens (shares) from the owner's balance. Only callable by the diamond
     * contract when not paused.
     * @param _assets The amount of assets to withdraw.
     * @param _receiver The address of the receiver of the withdrawn assets.
     * @param _owner The address of the owner whose tokens are burned.
     * @return shares The amount of shares burned.
     */
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        override
        nonReentrant
        onlyDiamond // #Zokyo-38
        returns (uint256 shares)
    {
        uint256 _maxAssets = maxWithdraw(_owner);
        if (_assets > _maxAssets) {
            revert ERC4626ExceededMaxWithdraw(_owner, _assets, _maxAssets);
        }

        uint256 lockedAssets = IViewFacet(diamondAddress).totalBorrowedUSD() / 1e12;

        if (totalAssets() - lockedAssets < _assets) {
            revert LpToken__LowFreeLiquidity(_owner, _assets, lockedAssets);
        }

        shares = previewWithdraw(_assets);
        _withdraw(_msgSender(), _receiver, _owner, _assets, shares);
    }

    /**
     * @notice Redeems tokens (shares) to withdraw assets from the owner's balance. Only callable by the diamond
     * contract when not paused.
     * @param _shares The number of shares to redeem.
     * @param _receiver The address of the receiver of the withdrawn assets.
     * @param _owner The address of the owner whose tokens are burned.
     * @return assets The amount of assets withdrawn.
     */
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        override
        nonReentrant
        onlyDiamond // #Zokyo-38
        returns (uint256 assets)
    {
        uint256 maxShares = maxRedeem(_owner);
        if (_shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(_owner, _shares, maxShares);
        }

        assets = previewRedeem(_shares);
        uint256 lockedAssets = IViewFacet(diamondAddress).totalBorrowedUSD() / 1e12;

        if ((totalAssets() - lockedAssets) < assets) {
            revert LpToken__LowFreeLiquidity(_owner, assets, lockedAssets);
        }

        _withdraw(_msgSender(), _receiver, _owner, assets, _shares);
    }

    // ========================== Internal Functions ========================== //

    /**
     * @dev Checks authorization for contract upgrades.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /**
     * @dev Internal function to handle asset deposits and minting of tokens (shares).
     * @param _caller The caller of the function.
     * @param _receiver The address of the receiver of the minted tokens.
     * @param _assets The amount of assets to deposit.
     * @param _shares The amount of shares to mint.
     */
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override {
        _mint(_receiver, _shares);
        emit Deposit(_caller, _receiver, _assets, _shares);
    }

    /**
     * @dev Internal function to handle asset withdrawals and burning of tokens (shares).
     * @param caller The caller of the function.
     * @param _receiver The address of the receiver of the withdrawn assets.
     * @param _owner The address of the owner whose tokens are burned.
     * @param _assets The amount of assets to withdraw.
     * @param _shares The amount of shares to burn.
     */
    function _withdraw(address caller, address _receiver, address _owner, uint256 _assets, uint256 _shares)
        internal
        override
    {
        if (caller != _owner) {
            _spendAllowance(_owner, caller, _shares);
        }
        _burn(_owner, _shares);
        emit Withdraw(caller, _receiver, _owner, _assets, _shares);
    }

    // ========================== View and Pure Functions ========================== //

    /**
     * @notice Retrieves the total assets managed by the diamond contract.
     * @return totalAsset The total assets in USD.
     */
    function totalAssets() public view override returns (uint256 totalAsset) {
        if (totalSupply() == 0) {
            return 0;
        }
        return (IViewFacet(diamondAddress).getUsdBalance() + IViewFacet(diamondAddress).totalBorrowedUSD()) / 1e12;
    }

}
