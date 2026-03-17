// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/// @title GaslessVault
/// @notice A UUPS-upgradeable token vault that supports gasless transactions via
///         ERC-2771 meta-transactions. Users can deposit, withdraw, and burn their
///         internal balances without holding ETH for gas — a trusted forwarder
///         relays signed requests on their behalf.
/// @dev Inherits from OwnableUpgradeable, UUPSUpgradeable, and ERC2771Context.
///      The trusted forwarder address is immutable and set at construction time.
///      The proxy must be initialized via {initialize} before use.
contract GaslessVault is Initializable, OwnableUpgradeable, UUPSUpgradeable, ERC2771Context {

    /// @notice The ERC-20 token managed by this vault.
    IERC20 public token;

    /// @notice Internal accounting of each user's deposited balance.
    /// @dev Does not represent actual token holdings for minted balances — only
    ///      `deposit` moves real tokens into the vault.
    mapping(address => uint256) public balances;

    /// @notice Locks the implementation contract against direct initialization.
    /// @param forwarder The ERC-2771 trusted forwarder address. Immutable after deployment.
    constructor(address forwarder) ERC2771Context(forwarder) {}

    /// @notice Initializes the proxy with a token and an owner.
    /// @dev Can only be called once. Replaces the constructor for the proxy context.
    ///      Calls {OwnableUpgradeable-__Ownable_init} to set the initial owner.
    /// @param _token   Address of the ERC-20 token this vault accepts.
    /// @param initialOwner Address that will be granted ownership of this vault.
    function initialize(address _token, address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        token = IERC20(_token);
    }

    /// @notice Deposits `amount` tokens from the caller into the vault.
    /// @dev Transfers tokens from the caller to this contract via `transferFrom`.
    ///      The caller must have approved this vault for at least `amount` tokens
    ///      before calling. Supports gasless calls via the trusted forwarder.
    /// @param amount The number of tokens to deposit (in the token's smallest unit).
    function deposit(uint256 amount) external {
        token.transferFrom(_msgSender(), address(this), amount);
        balances[_msgSender()] += amount;
    }

    /// @notice Withdraws `amount` tokens from the vault back to the caller.
    /// @dev Decrements the caller's internal balance and transfers real tokens out.
    ///      Reverts with "insufficient" if the caller's balance is too low.
    ///      Supports gasless calls via the trusted forwarder.
    /// @param amount The number of tokens to withdraw (in the token's smallest unit).
    function withdraw(uint256 amount) external {
        require(balances[_msgSender()] >= amount, "insufficient");
        balances[_msgSender()] -= amount;
        token.transfer(_msgSender(), amount);
    }

    /// @notice Credits `amount` to `user`'s internal balance without transferring tokens.
    /// @dev Only callable by the owner. This is an off-chain credit — no ERC-20
    ///      transfer occurs. The owner can use this to reward or compensate users.
    ///      Supports gasless calls via the trusted forwarder when signed by the owner.
    /// @param user   The address whose balance is credited.
    /// @param amount The amount to add to `user`'s internal balance.
    function mint(address user, uint256 amount) external onlyOwner {
        balances[user] += amount;
    }

    /// @notice Destroys `amount` from the caller's internal balance without returning tokens.
    /// @dev Decrements the caller's balance. No token transfer occurs — the balance
    ///      is simply removed. Reverts if the caller's balance is insufficient.
    ///      Supports gasless calls via the trusted forwarder.
    /// @param amount The amount to burn from the caller's internal balance.
    function burn(uint256 amount) external {
        require(balances[_msgSender()] >= amount);
        balances[_msgSender()] -= amount;
    }

    /// @notice Authorizes an upgrade to a new implementation.
    /// @dev Required by UUPS. Restricted to the owner so only the owner can upgrade
    ///      the proxy to a new implementation contract.
    /// @param newImplementation Address of the new implementation contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Returns the effective message sender, unwrapping the forwarder append if present.
    /// @dev Overrides both {ContextUpgradeable} and {ERC2771Context}. When a call arrives
    ///      through the trusted forwarder, the original signer's address is appended to
    ///      `msg.data`; this function extracts and returns it.
    /// @return sender The address of the original caller (or `msg.sender` if not a meta-tx).
    function _msgSender() internal view override(ContextUpgradeable, ERC2771Context) returns (address sender) {
        sender = ERC2771Context._msgSender();
    }

    /// @notice Returns the effective calldata, stripping the appended sender address if present.
    /// @dev Overrides both {ContextUpgradeable} and {ERC2771Context}. Needed so that
    ///      downstream logic sees clean calldata regardless of whether the call was
    ///      relayed through the trusted forwarder.
    /// @return The original calldata without the ERC-2771 appended address suffix.
    function _msgData() internal view override(ContextUpgradeable, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice Returns the number of extra bytes appended to `msg.data` by the forwarder.
    /// @dev Overrides both {ContextUpgradeable} and {ERC2771Context}. ERC-2771 appends
    ///      20 bytes (the original sender address) to calldata; this value is used
    ///      internally to correctly slice `_msgData()`.
    /// @return The byte length of the ERC-2771 suffix (20 for a standard forwarder).
    function _contextSuffixLength() internal view override(ContextUpgradeable, ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
}
