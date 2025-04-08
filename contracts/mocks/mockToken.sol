// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @custom:oz-upgrades-from test/Mocks/mockToken.sol:USDC
contract USDCF is ERC20Upgradeable, UUPSUpgradeable, OwnableUpgradeable {

    mapping(address => bool) faucetMinted;
    mapping(address => uint256) lastMinted;

    error AlreadyMinted(address);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() payable {
        _disableInitializers();
    }

    function initialize(string memory _name, string memory _symbol) public initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        // Mint initial tokens to the contract deployer (for testing purposes)
        _mint(msg.sender, 1_000_000 * (10 ** uint256(decimals())));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    function mint(address _account, uint256 _amount) external payable {
        _mint(_account, _amount);
    }

    function faucetMint(address _address) public {
        if (lastMinted[_address] + 7 days > block.timestamp) {
            revert AlreadyMinted(_address);
        }
        lastMinted[_address] = block.timestamp;
        _mint(_address, 10_000 * (10 ** uint256(decimals())));
    }

    function decimals() public pure override returns (uint8 _decimals) {
        return 6;
    }

    function walletLastMinted(address _userAddress) public view returns (uint256 _lastMinted) {
        return lastMinted[_userAddress];
    }

}
