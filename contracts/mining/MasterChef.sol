// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

contract MasterChef {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    // Info of each user.
    struct UserInfo {
        uint256 depositTime;
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 reward;
        uint256 rewardDebtLp; // Reward debt.
        uint256 rewardLp;
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20  lpToken; // Address of LP token contract.
        uint256 amount;  // How many LP tokens.
        uint256 lastRewardTime; // Last block number that Token distribution occurs.
        uint256 allocPoint; // How many allocation points assigned to this pool. Token to distribute per block.
        uint256 accTokenPerShare; // Accumulated Token per share, times 1e18. See below.
        address owner;
        address rewardToken;
        uint256 totalReward;
        uint256 epochId;
        uint256 reward;
        uint256 startTime;
        uint256 endTime;
        uint256 period;
        uint256 accRewardTokenPerShare; // Accumulated Token per share, times 1e18. See below.
    }

    address public governance;
    address public pendingGovernance;
    address public guardian;
    uint256 public guardianTime;
    uint256 public MaxStartLeadTime;
    uint256 public MaxPeriod;

    IERC20  public rewardToken;
    uint256 public totalReward;
    uint256 public totalGain;
    uint256 public intervalTime;

    uint256 public epochId;
    uint256 public reward;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public period;

    struct EpochReward {
        uint256 epochId;
        uint256 startTime;
        uint256 endTime;
        uint256 reward;
    }
    mapping(uint256 => EpochReward) public epochRewards;
    mapping(uint256 => mapping(uint256 => EpochReward)) public lpEpochRewards;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // Info of each pool.
    PoolInfo[] public poolInfos;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 reward, address rewardToken, uint256 rewardLp);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid,  uint256 amount);
    event SetLpReward(uint256 indexed pid, uint256 indexed epochId, uint256 startTime, uint256 period, uint256 reward);

    constructor(address _rewardToken, uint256 _maxStartLeadTime, uint256 _maxPeriod, uint256 _intervalTime) public {
        rewardToken = IERC20(_rewardToken);
        governance = msg.sender;
        guardian = msg.sender;
        MaxStartLeadTime = _maxStartLeadTime;
        MaxPeriod = _maxPeriod;
        intervalTime = _intervalTime;
        guardianTime = block.timestamp + 30 days;
    }

    function setGuardian(address _guardian) public {
        require(msg.sender == guardian, "!guardian");
        guardian = _guardian;
    }
    function addGuardianTime(uint256 _addTime) public {
        require(msg.sender == guardian || msg.sender == pendingGovernance, "!guardian");
        guardianTime = guardianTime.add(_addTime);
    }

    function acceptGovernance() public {
        require(msg.sender == pendingGovernance, "!pendingGovernance");
        governance = msg.sender;
        pendingGovernance = address(0);
    }
    function setPendingGovernance(address _pendingGovernance) public {
        require(msg.sender == governance, "!governance");
        pendingGovernance = _pendingGovernance;
    }

    function setIntervalTime(uint256 _intervalTime) public {
        require(msg.sender == governance, "!governance");
        intervalTime = _intervalTime;
    }
    function setAllocPoint(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        require(_pid < poolInfos.length, "!_pid");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfos[_pid].allocPoint).add(_allocPoint);
        require(totalAllocPoint > 0, "!totalAllocPoint");
        poolInfos[_pid].allocPoint = _allocPoint;
    }

    function addPool(address _lpToken, address _owner, uint256 _allocPoint, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        uint256 length = poolInfos.length;
        for (uint256 i = 0; i < length; i++) {
            require(_lpToken != address(poolInfos[i].lpToken), "!_lpToken");
        }
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfos.push(
            PoolInfo({
                lpToken: IERC20(_lpToken),
                amount: 0,
                lastRewardTime: block.timestamp,
                allocPoint: _allocPoint,
                accTokenPerShare: 0,
                owner: _owner,
                rewardToken: address(0),
                totalReward: 0,
                epochId: 0,
                reward: 0,
                startTime: 0,
                endTime: 0,
                period: 0,
                accRewardTokenPerShare: 0
            })
        );
    }

    function setLpRewardToken(uint256 _pid, address _rewardToken) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        require(msg.sender == pool.owner || msg.sender == governance, "!pool.owner");
        require(pool.rewardToken == address(0), "!pool.rewardToken");

        pool.rewardToken = _rewardToken;
    }

    function setLpOwner(uint256 _pid, address _owner) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        require(msg.sender == pool.owner || msg.sender == governance, "!pool.owner");

        pool.owner = _owner;
    }

    function setReward(uint256 _startTime, uint256 _period, uint256 _reward, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        require(endTime < block.timestamp, "!endTime");
        require(block.timestamp <= _startTime, "!_startTime");
        require(_startTime <= block.timestamp + MaxStartLeadTime, "!_startTime MaxStartLeadTime");
        require(_period > 0, "!_period");
        require(_period <= MaxPeriod, "!_period MaxPeriod");
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 _balance = rewardToken.balanceOf(address(this));
        require(_balance >= _reward, "!_reward");
        totalReward = totalReward.add(_reward);
        reward = _reward;
        startTime = _startTime;
        endTime = _startTime.add(_period);
        period = _period;
        epochId++;

        epochRewards[epochId] = EpochReward({
            epochId: epochId,
            startTime: _startTime,
            endTime: endTime,
            reward: _reward
        });
    }

    function setLpReward(uint256 _pid, uint256 _startTime, uint256 _period, uint256 _reward) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        require(msg.sender == pool.owner || msg.sender == governance, "!pool.owner");

        require(pool.rewardToken != address(0), "!pool.rewardToken");
        require(pool.endTime < block.timestamp, "!endTime");
        require(block.timestamp <= _startTime, "!_startTime");
        require(_startTime <= block.timestamp + MaxStartLeadTime, "!_startTime MaxStartLeadTime");
        require(_period > 0, "!_period");
        require(_period <= MaxPeriod, "!_period MaxPeriod");

        updatePool(_pid);
        IERC20(pool.rewardToken).safeTransferFrom(msg.sender, address(this), _reward);

        pool.totalReward = pool.totalReward.add(_reward);
        pool.epochId++;
        pool.reward = _reward;
        pool.startTime = _startTime;
        pool.endTime = _startTime.add(_period);
        pool.period = _period;

        lpEpochRewards[_pid][epochId] = EpochReward({
            epochId: epochId,
            startTime: _startTime,
            endTime: endTime,
            reward: _reward
        });
        emit SetLpReward(_pid, pool.epochId, _startTime, _period, _reward);
    }

    function getReward(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= startTime || _from >= endTime) {
            return 0;
        }

        if (_from < startTime) {
            _from = startTime; // [startTime, endTime)
        }

        if (_to > endTime) {
            _to = endTime;  // (startTime, endTime]
        }
        require(_from < _to, "!_from < _to");

        return _to.sub(_from).mul(reward).div(period);
    }

    function getLpReward(uint256 _pid, uint256 _from, uint256 _to) public view returns (uint256) {
        PoolInfo storage pool = poolInfos[_pid];
        uint256 _startTime = pool.startTime;
        uint256 _endTime = pool.endTime;
        if (_to <= _startTime || _from >= _endTime) {
            return 0;
        }

        if (_from < _startTime) {
            _from = _startTime; // [startTime, endTime)
        }

        if (_to > _endTime) {
            _to = _endTime;  // (startTime, endTime]
        }
        require(_from < _to, "!_from < _to");

        return _to.sub(_from).mul(pool.reward).div(pool.period);
    }

    // View function to see pending Token on frontend.
    function pendingToken(uint256 _pid, address _user) external view returns (uint256, uint256) {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][_user];
        uint256 _accTokenPerShare = pool.accTokenPerShare;
        uint256 _accRewardTokenPerShare = pool.accRewardTokenPerShare;
        uint256 _lpSupply = pool.amount;
        if (block.timestamp > pool.lastRewardTime && _lpSupply != 0) {
            if (block.timestamp > startTime && pool.lastRewardTime < endTime) {
                uint256 _rewardAmount =  getReward(pool.lastRewardTime, block.timestamp);
                if (_rewardAmount > 0) {
                    _rewardAmount = _rewardAmount.mul(pool.allocPoint).div(totalAllocPoint);
                    _accTokenPerShare = _accTokenPerShare.add(_rewardAmount.mul(1e18).div(_lpSupply));
                }
            }
            if (block.timestamp > pool.startTime && pool.lastRewardTime < pool.endTime) {
                uint256 _rewardLpAmount =  getLpReward(_pid, pool.lastRewardTime, block.timestamp);
                if (_rewardLpAmount > 0) {
                    _accRewardTokenPerShare = _accRewardTokenPerShare.add(_rewardLpAmount.mul(1e18).div(_lpSupply));
                }
            }
        }
        uint256 _reward = user.amount.mul(_accTokenPerShare).div(1e18).sub(user.rewardDebt);
        uint256 _rewardLp = user.amount.mul(_accRewardTokenPerShare).div(1e18).sub(user.rewardDebtLp);
        return (user.reward.add(_reward), user.rewardLp.add(_rewardLp));
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfos.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function _updateRewardPerShare(uint256 _pid) internal {
        PoolInfo storage pool = poolInfos[_pid];
        uint256 _lastRewardTime = pool.lastRewardTime;

        if (block.timestamp <= _lastRewardTime) {
            return;
        }
        if (_lastRewardTime >= pool.endTime) {
            return;
        }
        if (block.timestamp <= pool.startTime) {
            return;
        }

        uint256 _lpSupply = pool.amount;
        if (_lpSupply == 0) {
            return;
        }
        uint256 _rewardAmount = getLpReward(_pid, _lastRewardTime, block.timestamp);
        if (_rewardAmount > 0) {
            pool.accRewardTokenPerShare = pool.accRewardTokenPerShare.add(_rewardAmount.mul(1e18).div(_lpSupply));
        }
    }
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        require(_pid < poolInfos.length, "!_pid");

        _updateRewardPerShare(_pid);
        PoolInfo storage pool = poolInfos[_pid];
        uint256 _lastRewardTime = pool.lastRewardTime;
        if (block.timestamp <= _lastRewardTime) {
            return;
        }
        pool.lastRewardTime = block.timestamp;
        if (_lastRewardTime >= endTime) {
            return;
        }
        if (block.timestamp <= startTime) {
            return;
        }
        uint256 _lpSupply = pool.amount;
        if (_lpSupply == 0) {
            return;
        }

        uint256 _rewardAmount = getReward(_lastRewardTime, block.timestamp);
        if (_rewardAmount > 0) {
            _rewardAmount = _rewardAmount.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accTokenPerShare = pool.accTokenPerShare.add(_rewardAmount.mul(1e18).div(_lpSupply));
        }
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _reward = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
            user.reward = _reward.add(user.reward);
            uint256 _rewardLp = user.amount.mul(pool.accRewardTokenPerShare).div(1e18).sub(user.rewardDebtLp);
            user.rewardLp = _rewardLp.add(user.rewardLp);
        }
        pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        user.depositTime = block.timestamp;
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        user.rewardDebtLp = user.amount.mul(pool.accRewardTokenPerShare).div(1e18);
        pool.amount = pool.amount.add(_amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(user.amount >= _amount, "!_amount");
        require(block.timestamp >= user.depositTime + intervalTime, "!intervalTime");
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
        user.reward = _reward.add(user.reward);
        uint256 _rewardLp = user.amount.mul(pool.accRewardTokenPerShare).div(1e18).sub(user.rewardDebtLp);
        user.rewardLp = _rewardLp.add(user.rewardLp);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        user.rewardDebtLp = user.amount.mul(pool.accRewardTokenPerShare).div(1e18);
        pool.amount = pool.amount.sub(_amount);
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function harvest(uint256 _pid) public{
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
        _reward = _reward.add(user.reward);
        user.reward = 0;
        uint256 _rewardLp = user.amount.mul(pool.accRewardTokenPerShare).div(1e18).sub(user.rewardDebtLp);
        _rewardLp = _rewardLp.add(user.rewardLp);
        user.rewardLp = 0;
        address _rewardToken = pool.rewardToken;
        safeTokenTransfer(msg.sender, _reward, _rewardToken, _rewardLp);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        user.rewardDebtLp = user.amount.mul(pool.accRewardTokenPerShare).div(1e18);
        emit Harvest(msg.sender, _pid, _reward, _rewardToken, _rewardLp);
    }

    function withdrawAndHarvest(uint256 _pid, uint256 _amount) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(user.amount >= _amount, "!_amount");
        require(block.timestamp >= user.depositTime + intervalTime, "!intervalTime");
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
        _reward = _reward.add(user.reward);
        user.reward = 0;
        uint256 _rewardLp = user.amount.mul(pool.accRewardTokenPerShare).div(1e18).sub(user.rewardDebtLp);
        _rewardLp = _rewardLp.add(user.rewardLp);
        user.rewardLp = 0;
        address _rewardToken = pool.rewardToken;
        safeTokenTransfer(msg.sender, _reward, _rewardToken, _rewardLp);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        user.rewardDebtLp = user.amount.mul(pool.accRewardTokenPerShare).div(1e18);
        pool.amount = pool.amount.sub(_amount);
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _pid, _amount);
        emit Harvest(msg.sender, _pid, _reward, _rewardToken, _rewardLp);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(block.timestamp >= user.depositTime + 1, "!intervalTime"); // prevent flash loan
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.reward = 0;
        user.rewardDebtLp = 0;
        user.rewardLp = 0;
        pool.amount = pool.amount.sub(_amount);
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe rewardToken transfer function, just in case if rounding error causes pool to not have enough Token.
    function safeTokenTransfer(address _to, uint256 _amount, address _rewardToken, uint256 _amountLp) internal {
        if (_amount > 0) {
            uint256 _balance = rewardToken.balanceOf(address(this));
            if (_amount > _balance) {
                totalGain = totalGain.add(_balance);
                rewardToken.safeTransfer(_to, _balance);
            } else {
                totalGain = totalGain.add(_amount);
                rewardToken.safeTransfer(_to, _amount);
            }
        }
        if (_amountLp > 0) {
            uint256 _balanceOther = IERC20(_rewardToken).balanceOf(address(this));
            if (_amountLp > _balanceOther) {
                IERC20(_rewardToken).safeTransfer(_to, _balanceOther);
            } else {
                IERC20(_rewardToken).safeTransfer(_to, _amountLp);
            }
        }
    }

    function poolLength() external view returns (uint256) {
        return poolInfos.length;
    }

    function annualReward(uint256 _pid) public view returns (uint256 _annual, uint256 _annualLp){
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        // SECS_PER_YEAR  31_556_952  365.2425 days
        if (period > 0) {
            _annual = reward.mul(31556952).mul(pool.allocPoint).div(totalAllocPoint).div(period);
        }
        if (pool.period > 0) {
            _annualLp = pool.reward.mul(31556952).div(pool.period);
        }
    }

    function annualRewardPerShare(uint256 _pid) public view returns (uint256, uint256){
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        if (pool.amount == 0) {
            return (0, 0);
        }
        (uint256 _annual, uint256 _annualLp) = annualReward(_pid);
        return (_annual.mul(1e18).div(pool.amount), _annualLp.mul(1e18).div(pool.amount));
    }

    function sweepGuardian(address _token) public {
        require(msg.sender == guardian, "!guardian");
        require(block.timestamp > guardianTime, "!guardianTime");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(governance, _balance);
    }

    function sweep(address _token) public {
        require(msg.sender == governance, "!governance");
        require(_token != address(rewardToken), "!_token");
        uint256 length = poolInfos.length;
        for (uint256 i = 0; i < length; i++) {
            require(_token != address(poolInfos[i].lpToken), "!_token");
            require(_token != poolInfos[i].rewardToken, "!_token");
        }

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(governance, _balance);
    }

    function sweepLpToken(uint256 _pid) public {
        require(msg.sender == governance, "!governance");
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        IERC20 _token = pool.lpToken;

        uint256 _balance = _token.balanceOf(address(this));
        uint256 _amount = _balance.sub(pool.amount);
        _token.safeTransfer(governance, _amount);
    }
}
