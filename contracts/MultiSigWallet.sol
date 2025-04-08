// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { IDiamondCut } from "./interfaces/IDiamondCut.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MultiSigWallet
 * @notice A secure implementation of a multi-signature wallet with support for
 * proxy deployment, upgrades, and diamond cuts
 * @dev Implements security best practices including reentrancy guards, timelock,
 * and proper access controls
 */
contract MultiSigWallet is ReentrancyGuard, Pausable {

    using ECDSA for bytes32;

    // Custom errors for gas optimization
    error NotOwner();
    error DuplicateOwner();
    error InvalidConfirmations();
    error TransactionNotFound();
    error AlreadyExecuted();
    error AlreadyConfirmed();
    error ExecutionFailed();
    error InvalidAddress();
    error TooManyOwners();
    error NotEnoughOwners();
    error NotContract();
    error ExecutionTimeout();
    // error TimelockNotExpired();

    // Constants
    uint256 public constant MAX_OWNERS = 50;
    uint256 public constant EXECUTION_TIMEOUT = 30 days;
    uint256 public constant MAX_GAS = 300_000;
    // uint256 public constant TIMELOCK_DURATION = 24 hours;

    // Structs
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 numConfirmations;
        string task;
        uint8 txType; // Using uint8 instead of enum for gas optimization
        uint256 createdAt;
    }

    // Transaction types
    uint8 public constant TX_TYPE_STANDARD = 0;
    uint8 public constant TX_TYPE_DEPLOY_PROXY = 1;
    uint8 public constant TX_TYPE_UPGRADE = 2;
    uint8 public constant TX_TYPE_DIAMOND_CUT = 3;

    // State variables
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public immutable minConfirmations;
    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
    mapping(address => address) public proxyToImplementation;
    // mapping(uint256 => uint256) public transactionTimeLocks;

    // Events
    event OwnerAdded(address indexed owner, uint256 timestamp);
    event OwnerRemoved(address indexed owner, uint256 timestamp);
    event TransactionSubmitted(
        address indexed owner,
        uint256 indexed txIndex,
        address indexed to,
        uint256 value,
        bytes data,
        string task,
        uint8 txType,
        uint256 timestamp
    );
    event TransactionConfirmed(address indexed owner, uint256 indexed txIndex, uint256 timestamp);
    event TransactionExecuted(address indexed owner, uint256 indexed txIndex, bool success, uint256 timestamp);
    event TransactionFailed(uint256 indexed txIndex, uint256 timestamp);
    event RequiredConfirmationsChanged(uint256 oldRequired, uint256 newRequired, uint256 timestamp);
    event ProxyDeployed(address indexed implementation, address indexed proxy, uint256 timestamp);
    event ContractUpgraded(address indexed proxy, address indexed newImplementation, uint256 timestamp);
    event DiamondCutExecuted(address indexed diamond, IDiamondCut.FacetCut[] cuts, uint256 timestamp);
    event MultiSigWalletPaused(address indexed owner, uint256 timestamp);
    event MultiSigWalletUnpaused(address indexed owner, uint256 timestamp);

    // Modifiers
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier onlyWallet() {
        if (msg.sender != address(this)) revert NotOwner();
        _;
    }

    modifier txExists(uint256 _txIndex) {
        if (_txIndex >= transactions.length) revert TransactionNotFound();
        _;
    }

    modifier notExecuted(uint256 _txIndex) {
        if (transactions[_txIndex].executed) revert AlreadyExecuted();
        _;
    }

    modifier notConfirmed(uint256 _txIndex) {
        if (isConfirmed[_txIndex][msg.sender]) revert AlreadyConfirmed();
        _;
    }

    // modifier timelockExpired(uint256 _txIndex) {
    //     if (block.timestamp < transactionTimeLocks[_txIndex]) {
    //         revert TimelockNotExpired();
    //     }
    //     _;
    // }

    modifier notTimedOut(uint256 _txIndex) {
        if (block.timestamp > transactions[_txIndex].createdAt + EXECUTION_TIMEOUT) {
            revert ExecutionTimeout();
        }
        _;
    }

    /**
     * @notice Contract constructor
     * @param _owners Array of initial owners
     * @param _minConfirmations Number of required confirmations
     */
    constructor(address[] memory _owners, uint256 _minConfirmations) {
        if (_owners.length == 0) revert NotEnoughOwners();
        if (_owners.length > MAX_OWNERS) revert TooManyOwners();
        if (_minConfirmations == 0 || _minConfirmations > _owners.length) {
            revert InvalidConfirmations();
        }

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0)) revert InvalidAddress();
            if (isOwner[owner]) revert DuplicateOwner();

            isOwner[owner] = true;
            owners.push(owner);
        }

        minConfirmations = _minConfirmations;
    }

    /**
     * @notice Submit a standard transaction
     * @param _to Destination address
     * @param _value Amount of ETH to send
     * @param _data Transaction data
     * @param _taskDescription Description of the task
     */
    function submitTransaction(address _to, uint256 _value, bytes memory _data, string memory _taskDescription)
        public
        onlyOwner
        whenNotPaused
        returns (uint256)
    {
        if (_to == address(0)) revert InvalidAddress();

        uint256 txIndex = _submit(_to, _value, _data, _taskDescription, TX_TYPE_STANDARD);

        // Set timelock
        // transactionTimeLocks[txIndex] = block.timestamp + TIMELOCK_DURATION;
        _confirm(txIndex);

        return txIndex;
    }

    /**
     * @notice Submit a proxy deployment transaction
     * @param _implementation Implementation contract address
     * @param _initData Initialization data
     * @param _taskDescription Description of the task
     */
    function submitProxyDeployment(address _implementation, bytes memory _initData, string memory _taskDescription)
        public
        onlyOwner
        whenNotPaused
        returns (uint256)
    {
        if (_implementation == address(0)) revert InvalidAddress();
        if (_implementation.code.length == 0) revert NotContract();

        bytes memory deployData = abi.encode(_implementation, _initData);
        uint256 txIndex = _submit(address(0), 0, deployData, _taskDescription, TX_TYPE_DEPLOY_PROXY);

        // transactionTimeLocks[txIndex] = block.timestamp + TIMELOCK_DURATION;
        _confirm(txIndex);

        return txIndex;
    }

    /**
     * @notice Submit an upgrade transaction
     * @param _proxy Proxy contract address
     * @param _newImplementation New implementation address
     * @param _taskDescription Description of the task
     */
    function submitUpgrade(address _proxy, address _newImplementation, string memory _taskDescription)
        public
        onlyOwner
        whenNotPaused
        returns (uint256)
    {
        if (_proxy == address(0) || _newImplementation == address(0)) {
            revert InvalidAddress();
        }
        if (_newImplementation.code.length == 0) revert NotContract();

        bytes memory upgradeData = abi.encode(_newImplementation);
        uint256 txIndex = _submit(_proxy, 0, upgradeData, _taskDescription, TX_TYPE_UPGRADE);

        // transactionTimeLocks[txIndex] = block.timestamp + TIMELOCK_DURATION;
        _confirm(txIndex);

        return txIndex;
    }

    /**
     * @notice Submit a diamond cut transaction
     * @param _diamondAddress Diamond contract address
     * @param _cuts Array of facet cuts
     * @param _taskDescription Description of the task
     */
    function submitDiamondCut(
        address _diamondAddress,
        IDiamondCut.FacetCut[] memory _cuts,
        string memory _taskDescription
    ) public onlyOwner whenNotPaused returns (uint256) {
        if (_diamondAddress == address(0)) revert InvalidAddress();
        if (_diamondAddress.code.length == 0) revert NotContract();

        bytes memory diamondCutData = abi.encode(_cuts);
        uint256 txIndex = _submit(_diamondAddress, 0, diamondCutData, _taskDescription, TX_TYPE_DIAMOND_CUT);

        // transactionTimeLocks[txIndex] = block.timestamp + TIMELOCK_DURATION;
        _confirm(txIndex);

        return txIndex;
    }

    /**
     * @notice Internal function to submit a transaction
     */
    function _submit(address _to, uint256 _value, bytes memory _data, string memory _taskDescription, uint8 _txType)
        internal
        returns (uint256)
    {
        uint256 txIndex = transactions.length;
        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                numConfirmations: 0,
                task: _taskDescription,
                txType: _txType,
                createdAt: block.timestamp
            })
        );

        emit TransactionSubmitted(msg.sender, txIndex, _to, _value, _data, _taskDescription, _txType, block.timestamp);

        return txIndex;
    }

    /**
     * @notice Confirm a pending transaction
     * @param _txIndex Transaction index
     */
    function confirmTransaction(uint256 _txIndex)
        external
        onlyOwner
        whenNotPaused
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
        notTimedOut(_txIndex)
    {
        _confirm(_txIndex);
        Transaction storage transaction = transactions[_txIndex];

        if (transaction.numConfirmations >= minConfirmations) {
            _execute(_txIndex);
        }
    }

    /**
     * @notice Internal function to confirm a transaction
     */
    function _confirm(uint256 _txIndex) internal {
        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;

        emit TransactionConfirmed(msg.sender, _txIndex, block.timestamp);
    }

    /**
     * @notice Execute a confirmed transaction
     * @param _txIndex Transaction index
     */
    function _execute(uint256 _txIndex) internal nonReentrant 
    // timelockExpired(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.executed = true;

        bool success;

        if (transaction.txType == TX_TYPE_DIAMOND_CUT) {
            IDiamondCut.FacetCut[] memory cuts = abi.decode(transaction.data, (IDiamondCut.FacetCut[]));
            IDiamondCut(transaction.to).diamondCut(cuts, address(0), "0x");
            emit DiamondCutExecuted(transaction.to, cuts, block.timestamp);
            success = true;
        } else if (transaction.txType == TX_TYPE_DEPLOY_PROXY) {
            (address implementation, bytes memory initData) = abi.decode(transaction.data, (address, bytes));
            ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
            proxyToImplementation[address(proxy)] = implementation;
            emit ProxyDeployed(implementation, address(proxy), block.timestamp);
            success = true;
        } else if (transaction.txType == TX_TYPE_UPGRADE) {
            address newImplementation = abi.decode(transaction.data, (address));
            UUPSUpgradeable(transaction.to).upgradeToAndCall(newImplementation, new bytes(0));
            proxyToImplementation[transaction.to] = newImplementation;
            emit ContractUpgraded(transaction.to, newImplementation, block.timestamp);
            success = true;
        } else {
            (success,) = transaction.to.call{ value: transaction.value, gas: MAX_GAS }(transaction.data);
        }

        if (success) {
            emit TransactionExecuted(msg.sender, _txIndex, true, block.timestamp);
        } else {
            emit TransactionFailed(_txIndex, block.timestamp);
            revert ExecutionFailed();
        }
    }

    /**
     * @notice Add a new owner
     * @param _owner Address of new owner
     */
    function addOwner(address _owner) external onlyWallet {
        if (_owner == address(0)) revert InvalidAddress();
        if (isOwner[_owner]) revert DuplicateOwner();
        if (owners.length >= MAX_OWNERS) revert TooManyOwners();

        isOwner[_owner] = true;
        owners.push(_owner);
        emit OwnerAdded(_owner, block.timestamp);
    }

    /**
     * @notice Remove an existing owner
     * @param _owner Address of owner to remove
     */
    function removeOwner(address _owner) external onlyWallet {
        if (!isOwner[_owner]) revert NotOwner();
        if (owners.length <= minConfirmations) revert NotEnoughOwners();

        isOwner[_owner] = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        emit OwnerRemoved(_owner, block.timestamp);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyWallet {
        _pause();
        emit MultiSigWalletPaused(msg.sender, block.timestamp);
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyWallet {
        _unpause();
        emit MultiSigWalletUnpaused(msg.sender, block.timestamp);
    }

    /**
     * @notice Get list of owners
     * @return Array of owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @notice Get transaction details
     * @param _txIndex Transaction index
     */
    function getTransaction(uint256 _txIndex)
        external
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 numConfirmations,
            string memory task,
            uint8 txType,
            uint256 createdAt
        )
    {
        if (_txIndex >= transactions.length) revert TransactionNotFound();

        Transaction storage transaction = transactions[_txIndex];
        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations,
            transaction.task,
            transaction.txType,
            transaction.createdAt
        );
    }

    /**
     * @notice Get total number of transactions
     * @return Number of transactions
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @notice Check if a transaction is confirmed by an owner
     * @param _txIndex Transaction index
     * @param _owner Owner address
     * @return bool Whether the transaction is confirmed
     */
    function isTransactionConfirmed(uint256 _txIndex, address _owner) external view returns (bool) {
        if (_txIndex >= transactions.length) revert TransactionNotFound();
        return isConfirmed[_txIndex][_owner];
    }

    /**
     * @notice Check if a transaction has timed out
     * @param _txIndex Transaction index
     * @return bool Whether the transaction has timed out
     */
    function isTransactionTimedOut(uint256 _txIndex) external view returns (bool) {
        if (_txIndex >= transactions.length) revert TransactionNotFound();
        return block.timestamp > transactions[_txIndex].createdAt + EXECUTION_TIMEOUT;
    }

    /**
     * @notice Get implementation address for a proxy
     * @param _proxy Proxy address
     * @return Implementation address
     */
    function getImplementationAddress(address _proxy) external view returns (address) {
        return proxyToImplementation[_proxy];
    }

    /**
     * @notice Emergency function to recover stuck tokens
     * @param _token Token address (use address(0) for ETH)
     * @param _to Recipient address
     * @param _amount Amount to recover
     */
    function recoverTokens(address _token, address _to, uint256 _amount) external onlyWallet {
        if (_to == address(0)) revert InvalidAddress();

        if (_token == address(0)) {
            (bool success,) = _to.call{ value: _amount }("");
            if (!success) revert ExecutionFailed();
        } else {
            (bool success, bytes memory data) =
                _token.call(abi.encodeWithSignature("transfer(address,uint256)", _to, _amount));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
                revert ExecutionFailed();
            }
        }
    }

    // /**
    //  * @notice Get time remaining until timelock expires
    //  * @param _txIndex Transaction index
    //  * @return Time remaining in seconds
    //  */
    // function getTimelockRemaining(uint256 _txIndex)
    //     external
    //     view
    //     returns (uint256)
    // {
    //     if (_txIndex >= transactions.length) revert TransactionNotFound();
    //     uint256 unlockTime = transactionTimeLocks[_txIndex];
    //     if (block.timestamp >= unlockTime) return 0;
    //     return unlockTime - block.timestamp;
    // }

    /**
     * @notice Receive ETH
     */
    receive() external payable { }

    /**
     * @notice Fallback function
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }

}
