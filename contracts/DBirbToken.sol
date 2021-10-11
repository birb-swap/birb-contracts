pragma solidity 0.6.12;

import "./libs/BEP20.sol";

// DBirbToken with Governance.
contract DBirbToken is BEP20 {
    // Transfer tax rate in basis points. (default 5%)
    uint16 public transferTaxRate = 500;
    // Max transfer tax rate: 10%.
    uint16 public constant MAXIMUM_TRANSFER_TAX_RATE = 1000;
    // Addresses that excluded from tax
    mapping(address => bool) private _excludedFromTax;
    // Treasury Address
    address public treasuryAddress;

    // Burn address
    address public constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    // Max transfer amount rate in basis points. (default is 2% of total supply)
    uint16 public maxTransferAmountRate = 200;
    // Addresses that excluded from antiWhale
    mapping(address => bool) private _excludedFromAntiWhale;
    // Max token balance per wallet. (default is 100k)
    uint256 public maxBalancePerWallet = 10**23;
    // Addresses that excluded from antiFat :):):)
    mapping(address => bool) private _excludedFromAntiFat;

    // The operator can only update the transfer tax rate
    address private _operator;

    // Events
    event OperatorTransferred(
        address indexed previousOperator,
        address indexed newOperator
    );
    event TreasuryAddressUpdated(
        address indexed previousAddress,
        address indexed newAddress
    );
    event TransferTaxRateUpdated(
        address indexed operator,
        uint256 previousRate,
        uint256 newRate
    );
    event MaxTransferAmountRateUpdated(
        address indexed operator,
        uint256 previousRate,
        uint256 newRate
    );
    event MaxBalancePerWalletUpdated(
        address indexed operator,
        uint256 previousBalance,
        uint256 newBalance
    );

    modifier onlyOperator() {
        require(
            _operator == msg.sender,
            "operator: caller is not the operator"
        );
        _;
    }

    modifier antiWhale(
        address sender,
        address recipient,
        uint256 amount
    ) {
        if (maxTransferAmount() > 0) {
            if (
                _excludedFromAntiWhale[sender] == false &&
                _excludedFromAntiWhale[recipient] == false
            ) {
                require(
                    amount <= maxTransferAmount(),
                    "DBIRB::antiWhale: Transfer amount exceeds the maxTransferAmount"
                );
            }
        }
        _;
    }

    modifier antiFat(address recipient, uint256 amount) {
        uint256 recipientBalance = balanceOf(address(this));

        if (_excludedFromAntiFat[recipient] == false) {
            require(
                recipientBalance.add(amount) <= maxBalancePerWallet,
                "DBIRB::antiFat: Recipient balance exceeds the maxBalancePerWallet"
            );
        }
        _;
    }

    /**
     * @dev Update the treasury address.
     * Can only be called from the current treasury address.
     */
    function updateTreasuryAddress(address _treasuryAddress) external {
        require(
            treasuryAddress == msg.sender,
            "DBIRB::updateTreasuryAddress: Only allowed from the current treasury address."
        );
        emit TreasuryAddressUpdated(treasuryAddress, _treasuryAddress);
        treasuryAddress = _treasuryAddress;
    }

    /**
     * @dev Update the transfer tax rate.
     * Can only be called by the current operator.
     */
    function updateTransferTaxRate(uint16 _transferTaxRate)
        external
        onlyOperator
    {
        require(
            _transferTaxRate <= MAXIMUM_TRANSFER_TAX_RATE,
            "DBIRB::updateTransferTaxRate: Transfer tax rate must not exceed the maximum limit."
        );
        emit TransferTaxRateUpdated(
            msg.sender,
            transferTaxRate,
            _transferTaxRate
        );
        transferTaxRate = _transferTaxRate;
    }

    /**
     * @dev Returns the address is excluded from tax or not.
     */
    function isExcludedFromTax(address _account) public view returns (bool) {
        return _excludedFromTax[_account];
    }

    /**
     * @dev Exclude or include an address from tax.
     * Can only be called by the current operator.
     */
    function excludeFromTax(address _account, bool _excluded)
        external
        onlyOperator
    {
        _excludedFromTax[_account] = _excluded;
    }

    /**
     * @dev Returns the max transfer amount.
     */
    function maxTransferAmount() public view returns (uint256) {
        return totalSupply().mul(maxTransferAmountRate).div(10000);
    }

    /**
     * @dev Update the max transfer amount rate.
     * Can only be called by the current operator.
     */
    function updateMaxTransferAmountRate(uint16 _maxTransferAmountRate)
        external
        onlyOperator
    {
        require(
            _maxTransferAmountRate <= 10000,
            "DBIRB::updateMaxTransferAmountRate: Max transfer amount rate must not exceed the maximum rate."
        );
        emit MaxTransferAmountRateUpdated(
            msg.sender,
            maxTransferAmountRate,
            _maxTransferAmountRate
        );
        maxTransferAmountRate = _maxTransferAmountRate;
    }

    /**
     * @dev Returns the address is excluded from antiWhale or not.
     */
    function isExcludedFromAntiWhale(address _account)
        external
        view
        returns (bool)
    {
        return _excludedFromAntiWhale[_account];
    }

    /**
     * @dev Exclude or include an address from antiWhale.
     * Can only be called by the current operator.
     */
    function excludeFromAntiWhale(address _account, bool _excluded)
        external
        onlyOperator
    {
        _excludedFromAntiWhale[_account] = _excluded;
    }

    /**
     * @dev Update the max balance per wallet.
     * Can only be called by the current operator.
     */
    function updateMaxBalancePerWallet(uint16 _maxBalancePerWallet)
        external
        onlyOperator
    {
        require(
            _maxBalancePerWallet <= 10000,
            "DBIRB::updateMaxBalancePerWallet: Max transfer amount rate must not exceed the maximum rate."
        );
        emit MaxBalancePerWalletUpdated(
            msg.sender,
            maxBalancePerWallet,
            _maxBalancePerWallet
        );
        maxBalancePerWallet = _maxBalancePerWallet;
    }

    /**
     * @dev Returns the address is excluded from antiFat or not.
     */
    function isExcludedFromAntiFat(address _account)
        public
        view
        returns (bool)
    {
        return _excludedFromAntiFat[_account];
    }

    /**
     * @dev Exclude or include an address from antiFat.
     * Can only be called by the current operator.
     */
    function excludeFromAntiFat(address _account, bool _excluded)
        external
        onlyOperator
    {
        _excludedFromAntiFat[_account] = _excluded;
    }

    /**
     * @dev Returns the address of the current operator.
     */
    function operator() public view returns (address) {
        return _operator;
    }

    /**
     * @dev Transfers operator of the contract to a new account (`newOperator`).
     * Can only be called by the current operator.
     */
    function transferOperator(address newOperator) external onlyOperator {
        require(
            newOperator != address(0),
            "DBIRB::transferOperator: new operator is the zero address"
        );
        emit OperatorTransferred(_operator, newOperator);
        _operator = newOperator;
    }

    constructor() public BEP20("Diamond Birb", "DBIRB") {
        _operator = _msgSender();
        emit OperatorTransferred(address(0), _operator);
        treasuryAddress = _msgSender();
        emit TreasuryAddressUpdated(address(0), treasuryAddress);

        _excludedFromTax[msg.sender] = true;
        _excludedFromTax[address(0)] = true;
        _excludedFromTax[BURN_ADDRESS] = true;

        _excludedFromAntiWhale[msg.sender] = true;
        _excludedFromAntiWhale[address(0)] = true;
        _excludedFromAntiWhale[BURN_ADDRESS] = true;

        _excludedFromAntiFat[msg.sender] = true;
        _excludedFromAntiFat[address(0)] = true;
        _excludedFromAntiFat[BURN_ADDRESS] = true;
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
    }

    /// @dev overrides transfer function to meet tokenomics of FSWAP
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    )
        internal
        virtual
        override
        antiWhale(sender, recipient, amount)
        antiFat(recipient, amount)
    {
        if (isExcludedFromTax(sender) || isExcludedFromTax(recipient)) {
            super._transfer(sender, recipient, amount);
        } else {
            uint256 taxAmount = amount.mul(transferTaxRate).div(10000);
            uint256 sendAmount = amount.sub(taxAmount);
            require(
                amount == sendAmount + taxAmount,
                "DBIRB::transfer: Tax value invalid"
            );

            if (taxAmount > 0) {
                super._transfer(sender, treasuryAddress, taxAmount);
            }
            super._transfer(sender, recipient, sendAmount);
            amount = sendAmount;
        }
    }

    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    /// @notice A record of each accounts delegate
    mapping(address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator) external view returns (address) {
        return _delegates[delegator];
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "DBIRB::delegateBySig: invalid signature"
        );
        require(
            nonce == nonces[signatory]++,
            "DBIRB::delegateBySig: invalid nonce"
        );
        require(now <= expiry, "DBIRB::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return
            nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        require(
            blockNumber < block.number,
            "DBIRB::getPriorVotes: not yet determined"
        );

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying DBIRBs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0
                    ? checkpoints[srcRep][srcRepNum - 1].votes
                    : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0
                    ? checkpoints[dstRep][dstRepNum - 1].votes
                    : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        uint32 blockNumber = safe32(
            block.number,
            "DBIRB::_writeCheckpoint: block number exceeds 32 bits"
        );

        if (
            nCheckpoints > 0 &&
            checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber
        ) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(
                blockNumber,
                newVotes
            );
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint256 n, string memory errorMessage)
        internal
        pure
        returns (uint32)
    {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
