// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ClaimToken
/// @notice Minimal ERC20-like claim token used for one side of an option series.
/// @dev The deploying `OptionSeries` is the only account allowed to mint or burn
///      claims. This keeps token supply exactly tied to ETH collateral accounting
///      in the owning series.
contract ClaimToken {
    /// @notice Human-readable token name.
    string public name;
    /// @notice ERC20-style token symbol.
    string public symbol;
    /// @notice Claim tokens use 18 decimals so token amounts align with wei.
    uint8 public constant decimals = 18;

    /// @notice Option series contract that controls minting and burning.
    address public immutable series;
    /// @notice Total outstanding claim token supply.
    uint256 public totalSupply;

    /// @notice ERC20-style balances by account.
    mapping(address account => uint256 balance) public balanceOf;
    /// @notice ERC20-style allowances by owner and spender.
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    /// @notice Caller is not the owning option series.
    error Unauthorized();
    /// @notice Account balance is lower than the requested transfer or burn.
    error InsufficientBalance();
    /// @notice Allowance is lower than the requested transfer amount.
    error InsufficientAllowance();
    /// @notice Recipient is the zero address.
    error InvalidRecipient();

    /// @notice Emitted on mint, burn, and transfer.
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when an owner sets or spends a finite allowance.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @param name_ ERC20-style token name.
    /// @param symbol_ ERC20-style token symbol.
    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        series = msg.sender;
    }

    /// @dev Restricts supply-changing operations to the owning option series.
    modifier onlySeries() {
        if (msg.sender != series) revert Unauthorized();
        _;
    }

    /// @notice Approves `spender` to transfer up to `amount` from the caller.
    /// @return Always true on success, following the ERC20 convention.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers `amount` tokens from the caller to `to`.
    /// @return Always true on success, following the ERC20 convention.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfers `amount` tokens from `from` to `to` using caller allowance.
    /// @dev A max-uint allowance is treated as infinite and is not decremented.
    /// @return Always true on success, following the ERC20 convention.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, amount);
        return true;
    }

    /// @notice Mints claim tokens to `to`.
    /// @dev Only the owning option series can call this during ETH splitting.
    function mint(address to, uint256 amount) external onlySeries {
        if (to == address(0)) revert InvalidRecipient();

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @notice Burns claim tokens from `from`.
    /// @dev Only the owning option series can call this during combine or redemption.
    function burn(address from, uint256 amount) external onlySeries {
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance();

        unchecked {
            balanceOf[from] = balance - amount;
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    /// @dev Shared transfer implementation for direct and allowance-based transfers.
    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidRecipient();

        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance();

        unchecked {
            balanceOf[from] = balance - amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }
}
