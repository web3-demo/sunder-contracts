// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";

contract EToken {
    /// @dev EIP-20 token name for this token
    string public name;

    /// @dev EIP-20 token symbol for this token
    string public symbol;

    /// @dev EIP-20 token decimals for this token
    uint8 public decimals;

    /// @dev Total number of tokens in circulation
    uint256 public totalSupply;

    /// @dev Allowance amounts on behalf of others
    mapping (address => mapping (address => uint256)) internal allowances;

    /// @dev Official record of token balances for each account
    mapping (address => uint256) internal balances;

    address public governance;
    address public pendingGovernance;
    address public convController;
    address public vault;

    /// @dev The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev The standard EIP-20 approval event
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event Mint(address indexed account, uint256 amount);
    event Burn(address indexed account, uint256 amount);

    function initialize(address _governance, uint8  _decimals, bytes calldata _name, bytes calldata _symbol) external {
        require(governance == address(0), 'initialize: can only initialize once');
        require(_governance != address(0), 'initialize: invalid governance address');
        governance = _governance;
        convController = msg.sender;
        name = string(_name);
        symbol = string(_symbol);
        decimals = _decimals;
    }

    function allowance(address account, address spender) external view returns (uint256) {
        return allowances[account][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address dst, uint256 amount) external returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    function transferFrom(address src, address dst, uint256 amount) external returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowances[src][spender];

        if (spender != src && spenderAllowance != uint256(-1)) {
            uint256 newAllowance = sub256(spenderAllowance, amount, "transferFrom: transfer amount exceeds spender allowance");
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    function _transferTokens(address src, address dst, uint256 amount) internal {
        require(src != address(0), "_transferTokens: cannot transfer from the zero address");
        require(dst != address(0), "_transferTokens: cannot transfer to the zero address");

        balances[src] = sub256(balances[src], amount, "_transferTokens: transfer amount exceeds balance");
        balances[dst] = add256(balances[dst], amount, "_transferTokens: transfer amount overflows");
        emit Transfer(src, dst, amount);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "!pendingGovernance");
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    function setPendingGovernance(address _pendingGovernance) external {
        require(msg.sender == governance, "!governance");
        pendingGovernance = _pendingGovernance;
    }

    function setConvController(address _convController) external {
        require(msg.sender == governance, "!governance");
        convController = _convController;
    }

    function setVault(address _vault) external {
        require(msg.sender == governance, "!governance");
        vault = _vault;
    }

    function mint(address account, uint256 amount) external {
       require(msg.sender == convController || msg.sender == vault, "NOT OPERATOR");
       _mint(account,amount);
       emit Mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(msg.sender == convController || msg.sender == vault, "NOT OPERATOR");
        _burn(account,amount);
        emit Burn(account, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        totalSupply = add256(totalSupply, amount, "ERC20: mint amount overflows");
        balances[account] = add256(balances[account], amount, "ERC20: mint amount overflows");

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        balances[account] = sub256(balances[account], amount, "ERC20: burn amount exceeds balance");
        totalSupply = sub256(totalSupply, amount, "ERC20: burn amount exceeds balance");

        emit Transfer(account, address(0), amount);
    }

    function add256(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub256(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function sweep(address _token) external {
        require(msg.sender == governance, "!governance");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(governance, _balance);
    }
}
