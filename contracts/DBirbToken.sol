pragma solidity 0.6.12;

import "./libs/BEP20.sol";

// DBirbToken with Governance.
contract DBirbToken is BEP20 {
    // Burn address
    address public constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    // Max token balance per wallet. (default is 100k)
    uint256 public maxBalancePerWallet = 100000 ether;
    // Addresses that excluded from antiFat :):):)
    mapping(address => bool) private _excludedFromAntiFat;
    
    uint256 public constant ALWAYS_ALLOWED_WALLET_BALANCE = 100 ether;

    // The operator can only update the token settings
    address private _operator;

    // Events
    event OperatorTransferred(
        address indexed previousOperator,
        address indexed newOperator
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

    modifier antiFat(address recipient, uint256 amount) {
        uint256 recipientBalance = balanceOf(recipient);

        if (_excludedFromAntiFat[recipient] == false) {
            require(
                recipientBalance.add(amount) <= availableBalancePerWallet(),
                "DBIRB::antiFat: Recipient balance exceeds the maxBalancePerWallet"
            );
        }
        _;
    }

    /**
     * @dev Returns the max balance per wallet.
     */
    function availableBalancePerWallet() public view returns (uint256) {
        if (maxBalancePerWallet < ALWAYS_ALLOWED_WALLET_BALANCE) {
            return ALWAYS_ALLOWED_WALLET_BALANCE;
        }
        return maxBalancePerWallet;
    }

    /**
     * @dev Update the max balance per wallet.
     * Can only be called by the current operator.
     */
    function updateMaxBalancePerWallet(uint256 _maxBalancePerWallet)
        external
        onlyOperator
    {
        require(
            _maxBalancePerWallet >= ALWAYS_ALLOWED_WALLET_BALANCE,
            "DBIRB::updateMaxBalancePerWallet: Max balance per wallet must bigger than 10000 ether."
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
        antiFat(recipient, amount)
    {
        super._transfer(sender, recipient, amount);
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
