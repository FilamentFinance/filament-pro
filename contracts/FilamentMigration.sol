// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FilamentMigration
 * @dev A contract for managing migration credits using USDC tokens.
 * Allows allocation of USDC credits to recipients and facilitates the claiming of allocated credits.
 */
contract FilamentMigration is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    /// @notice USDC token used for migration credits.
    IERC20 public usdc;

    /// @notice Total USDC allocated for migration credits.
    uint256 public totalUSDCAllocated;

    /// @notice Mapping of addresses to their respective USDC credits.
    mapping(address => uint256) public usdcCredits;

    /// @dev Error thrown when array lengths for recipients and amounts do not match.
    error FilamentMigration__ArrayLengthMismatch();

    /// @dev Error thrown when the maximum supply is reached.
    error FilamentMigration__MaxSupplyReached();

    /// @dev Error thrown when a user does not have enough credits to claim.
    error FilamentMigration__NotEnoughCredtis();

    /// @dev Error thrown when an invalid value is provided.
    error FilamentMigration__InvalidValue();

    /// @notice Event emitted when a user claims USDC credits.
    /// @param user The address of the user claiming the credits.
    /// @param amount The amount of USDC claimed.
    event UsdcClaimed(address indexed user, uint256 amount);

    /// @notice Event emitted when total USDC allocated is updated.
    /// @param amount The updated total USDC allocated.
    event TotalUsdcAllocated(uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() payable {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with the USDC token address.
     * @param _usdc The address of the USDC token contract.
     */
    function initialize(address _usdc) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        usdc = IERC20(_usdc);
    }

    /**
     * @notice Pauses contract operations.
     * @dev Only callable by the owner.
     */
    function pause() external payable onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses contract operations.
     * @dev Only callable by the owner.
     */
    function unpause() external payable onlyOwner {
        _unpause();
    }

    /**
     * @notice Allocates USDC credits to multiple recipients.
     * @param _recipients The array of recipient addresses.
     * @param _amounts The array of credit amounts corresponding to each recipient.
     * @dev The lengths of `_recipients` and `_amounts` must match.
     */
    function setUsdcCredits(address[] calldata _recipients, uint256[] calldata _amounts) external onlyOwner {
        require(_recipients.length == _amounts.length, FilamentMigration__ArrayLengthMismatch());
        uint256 _totalCreditsAllocated = totalUSDCAllocated;
        uint256 aLength = _recipients.length;
        for (uint256 i; i < aLength;) {
            usdcCredits[_recipients[i]] += _amounts[i]; // Users can get extra Credits in phases
            _totalCreditsAllocated = _totalCreditsAllocated + _amounts[i];
            unchecked {
                ++i;
            }
        }
        totalUSDCAllocated = _totalCreditsAllocated;
        emit TotalUsdcAllocated(totalUSDCAllocated);
    }

    /**
     * @notice Allows a user to claim their allocated USDC credits.
     * @dev Reverts if the caller has no credits to claim or if the contract is paused.
     */
    function claim() external nonReentrant whenNotPaused {
        require(usdcCredits[msg.sender] != 0, FilamentMigration__NotEnoughCredtis());
        usdc.safeTransfer(msg.sender, usdcCredits[msg.sender]);
        emit UsdcClaimed(msg.sender, usdcCredits[msg.sender]);
        usdcCredits[msg.sender] = 0;
    }

    /**
     * @notice Returns the USDC balance of the contract.
     * @return balance The USDC balance of the contract.
     */
    function usdcBalance() public view returns (uint256 balance) {
        return usdc.balanceOf(address(this));
    }

    /**
     * @notice Authorizes an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation contract.
     * @dev Can only be called by the owner.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

}
