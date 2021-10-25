pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";

import "./libs/IDBirbReferral.sol";
import "./libs/SafeBEP20.sol";
import "./DBirbToken.sol";
import "./DBirbSyrupBar.sol";

// DBirbMasterChef is the master of DBIRB. He can make DBIRB and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once DBIRB is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract DBirbMasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of DBIRBs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accDBirbPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accDBirbPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 lpSupply; // Pool lp supply
        uint256 allocPoint; // How many allocation points assigned to this pool. DBIRBs to distribute per block.
        uint256 lastRewardBlock; // Last block number that DBIRBs distribution occurs.
        uint256 accDBirbPerShare; // Accumulated DBIRBs per share, times 1e12. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
    }

    // The DBIRB TOKEN!
    DBirbToken public dbirb;
    // The SYRUP TOKEN!
    DBirbSyrupBar public syrup;
    // Dev address.
    address public devaddr;
    // Deposit Fee address
    address public feeAddress;
    // DBIRB tokens created per block.
    uint256 public dbirbPerBlock;
    // Maximum emission rate
    uint256 public constant MAXIMUM_EMISSON_RATE = 10**24;

    // Bonus muliplier for early dbirb makers.
    uint256 public BONUS_MULTIPLIER = 1;
    
    // DBirb referral contract address.
    IDBirbReferral public dbirbReferral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 0;
    // Max referral commission rate: 5%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 500;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // Max deposit fee per pools: 20%
    uint16 public constant MAX_DEPOSIT_FEE = 2000;
    // The block number when DBIRB mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 dbirbPerBlock);
    event SetDBirbReferral(address newReferral);
    event SetReferralCommissionRate(uint16 newCommissionRate);
    event ReferralCommissionPaid(
        address indexed user,
        address indexed referrer,
        uint256 commissionAmount
    );

    constructor(
        DBirbToken _dbirb,
        DBirbSyrupBar _syrup,
        address _devaddr,
        address _feeAddress,
        uint256 _dbirbPerBlock,
        uint256 _startBlock
    ) public {
        dbirb = _dbirb;
        syrup = _syrup;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        dbirbPerBlock = _dbirbPerBlock;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: _dbirb,
                lpSupply: 0,
                allocPoint: 1000,
                lastRewardBlock: startBlock,
                depositFeeBP: 0,
                accDBirbPerShare: 0
            })
        );

        totalAllocPoint = 1000;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) external onlyOwner nonDuplicated(_lpToken) {
        require(
            _depositFeeBP <= MAX_DEPOSIT_FEE,
            "add: invalid deposit fee basis points"
        );
        _lpToken.balanceOf(address(this));      // Check if lptoken is the actual token contract

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                lpSupply: 0,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accDBirbPerShare: 0,
                depositFeeBP: _depositFeeBP
            })
        );
        updateStakingPool();
    }

    // Update the given pool's DBIRB allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) external onlyOwner {
        require(
            _depositFeeBP < MAX_DEPOSIT_FEE,
            "set: invalid deposit fee basis points"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(
                _allocPoint
            );
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(
                points
            );
            poolInfo[0].allocPoint = points;
        }
    }
    
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending DBIRBs on frontend.
    function pendingDBirb(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDBirbPerShare = pool.accDBirbPerShare;
        if (block.number > pool.lastRewardBlock && pool.lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 dbirbReward = multiplier
                .mul(dbirbPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accDBirbPerShare = accDBirbPerShare.add(
                dbirbReward.mul(1e12).div(pool.lpSupply)
            );
        }
        return user.amount.mul(accDBirbPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        
        if (pool.lpSupply == 0 || totalAllocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 dbirbReward = multiplier
            .mul(dbirbPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        dbirb.mint(devaddr, dbirbReward.div(10));
        dbirb.mint(address(syrup), dbirbReward);
        pool.accDBirbPerShare = pool.accDBirbPerShare.add(
            dbirbReward.mul(1e12).div(pool.lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for DBIRB allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) external {
        require(_pid != 0, "deposit DBIRB by staking");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        // Record new referrer
        if (
            _amount > 0 &&
            address(dbirbReferral) != address(0) &&
            _referrer != address(0) &&
            _referrer != msg.sender &&
            _referrer != dbirbReferral.getReferrer(msg.sender)
        ) {
            dbirbReferral.recordReferral(msg.sender, _referrer);
        }

        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accDBirbPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeDBirbTransfer(msg.sender, pending);
                payReferralCommission(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            _amount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);
            uint256 depositFee = 0;
            if (pool.depositFeeBP > 0) {
                depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                if (depositFee > 0) {
                    pool.lpToken.safeTransfer(feeAddress, depositFee);
                }
            }
            user.amount = user.amount.add(_amount).sub(depositFee);
            pool.lpSupply = pool.lpSupply.add(_amount).sub(depositFee);
        }
        user.rewardDebt = user.amount.mul(pool.accDBirbPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {
        require(_pid != 0, "withdraw DBIRB by unstaking");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good(user balance not enough)");
        require(pool.lpSupply >= _amount, "withdraw: not good(pool balance not enough)");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accDBirbPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeDBirbTransfer(msg.sender, pending);
            payReferralCommission(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpSupply = pool.lpSupply.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDBirbPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake DBIRB tokens to MasterChef
    function enterStaking(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accDBirbPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeDBirbTransfer(msg.sender, pending);
                payReferralCommission(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            _amount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);
            uint256 depositFee = 0;
            if (pool.depositFeeBP > 0) {
                depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                if (depositFee > 0) {
                    pool.lpToken.safeTransfer(feeAddress, depositFee);
                }
            }
            user.amount = user.amount.add(_amount).sub(depositFee);
            pool.lpSupply = pool.lpSupply.add(_amount).sub(depositFee);
        }
        user.rewardDebt = user.amount.mul(pool.accDBirbPerShare).div(1e12);

        syrup.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw DBIRB tokens from STAKING.
    function leaveStaking(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good(user balance not enough)");
        require(pool.lpSupply >= _amount, "withdraw: not good(pool balance not enough)");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accDBirbPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeDBirbTransfer(msg.sender, pending);
            payReferralCommission(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpSupply = pool.lpSupply.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDBirbPerShare).div(1e12);

        syrup.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpSupply = pool.lpSupply.sub(user.amount);
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe dbirb transfer function, just in case if rounding error causes pool to not have enough DBIRBs.
    function safeDBirbTransfer(address _to, uint256 _amount) internal {
        syrup.safeDBirbTransfer(_to, _amount);
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) external {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    // Update emission rate
    function updateEmissionRate(uint256 _dbirbPerBlock) external onlyOwner {
        require(_dbirbPerBlock <= MAXIMUM_EMISSON_RATE, "Too high");
        massUpdatePools();
        dbirbPerBlock = _dbirbPerBlock;
        emit UpdateEmissionRate(msg.sender, _dbirbPerBlock);
    }

    // Update the dbirb referral contract address by the owner
    function setDBirbReferral(IDBirbReferral _dbirbReferral) external onlyOwner {
        require(
            address(dbirbReferral) != address(_dbirbReferral),
            "Already set"
        );
        dbirbReferral = _dbirbReferral;
        emit SetDBirbReferral(address(_dbirbReferral));
    }

    // Update referral commission rate by the owner
    function setReferralCommissionRate(uint16 _referralCommissionRate)
        external
        onlyOwner
    {
        require(
            _referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE,
            "setReferralCommissionRate: invalid referral commission rate basis points"
        );
        referralCommissionRate = _referralCommissionRate;
        emit SetReferralCommissionRate(_referralCommissionRate);
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (
            address(dbirbReferral) != address(0) && referralCommissionRate > 0
        ) {
            address referrer = dbirbReferral.getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(
                10000
            );

            if (referrer != address(0) && commissionAmount > 0) {
                dbirb.mint(referrer, commissionAmount);
                dbirbReferral.recordReferralCommission(
                    referrer,
                    commissionAmount
                );
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }
}
