// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC2771Forwarder} from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {GaslessVault} from "../src/GaslessVault.sol";
import {TestToken} from "../src/TestToken.sol";

contract GaslessVaultTest is Test {
    GaslessVault public vault;
    TestToken public token;
    ERC2771Forwarder public forwarder;

    address public owner;
    address public user;
    address public relayer;

    uint256 internal ownerKey;
    uint256 internal userKey;

    function setUp() public {
        ownerKey = 0xA11CE;
        userKey  = 0xB0B;

        owner   = vm.addr(ownerKey);
        user    = vm.addr(userKey);
        relayer = makeAddr("relayer");

        forwarder = new ERC2771Forwarder("GaslessForwarder");
        token     = new TestToken();

        GaslessVault implementation = new GaslessVault(address(forwarder));

        bytes memory initData = abi.encodeCall(
            GaslessVault.initialize,
            (address(token), owner)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vault = GaslessVault(address(proxy));

        token.transfer(user, 500 ether);
        vm.prank(user);
        token.approve(address(vault), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("GaslessForwarder")),
            keccak256(bytes("1")),
            block.chainid,
            address(forwarder)
        ));
    }

    function _buildAndSignRequest(
        uint256 signerKey,
        address to,
        bytes memory data,
        uint48 deadline
    ) internal view returns (ERC2771Forwarder.ForwardRequestData memory) {
        address signer = vm.addr(signerKey);
        uint256 nonce  = forwarder.nonces(signer);

        bytes32 structHash = keccak256(abi.encode(
            keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)"),
            signer,
            to,
            uint256(0),
            uint256(200_000),
            nonce,
            deadline,
            keccak256(data)
        ));

        bytes32 digest = MessageHashUtils.toTypedDataHash(_domainSeparator(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        return ERC2771Forwarder.ForwardRequestData({
            from:      signer,
            to:        to,
            value:     0,
            gas:       200_000,
            deadline:  deadline,
            data:      data,
            signature: sig
        });
    }

    // ─────────────────────────────────────────────────────────────
    // Initialization
    // ─────────────────────────────────────────────────────────────

    function test_InitializesOwner() public view {
        assertEq(vault.owner(), owner);
    }

    function test_InitializesToken() public view {
        assertEq(address(vault.token()), address(token));
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        vault.initialize(address(token), owner);
    }

    // ─────────────────────────────────────────────────────────────
    // Deposit
    // ─────────────────────────────────────────────────────────────

    function test_DepositUpdatesBalance() public {
        vm.prank(user);
        vault.deposit(100 ether);

        assertEq(vault.balances(user), 100 ether);
    }

    function test_DepositTransfersTokensToVault() public {
        uint256 vaultBefore = token.balanceOf(address(vault));

        vm.prank(user);
        vault.deposit(100 ether);

        assertEq(token.balanceOf(address(vault)), vaultBefore + 100 ether);
        assertEq(token.balanceOf(user), 400 ether);
    }

    function test_DepositRevertsWithoutApproval() public {
        address stranger = makeAddr("stranger");
        token.transfer(stranger, 50 ether);

        vm.prank(stranger);
        vm.expectRevert();
        vault.deposit(50 ether);
    }

    function test_DepositRevertsWithInsufficientBalance() public {
        address poor = makeAddr("poor");

        vm.prank(poor);
        token.approve(address(vault), type(uint256).max);

        vm.prank(poor);
        vm.expectRevert();
        vault.deposit(1 ether);
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, 500 ether);

        vm.prank(user);
        vault.deposit(amount);

        assertEq(vault.balances(user), amount);
        assertEq(token.balanceOf(address(vault)), amount);
    }

    // ─────────────────────────────────────────────────────────────
    // Withdraw
    // ─────────────────────────────────────────────────────────────

    function test_WithdrawUpdatesBalance() public {
        vm.prank(user);
        vault.deposit(100 ether);

        vm.prank(user);
        vault.withdraw(60 ether);

        assertEq(vault.balances(user), 40 ether);
    }

    function test_WithdrawReturnsTokensToUser() public {
        vm.prank(user);
        vault.deposit(100 ether);

        vm.prank(user);
        vault.withdraw(100 ether);

        assertEq(token.balanceOf(user), 500 ether);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function test_WithdrawRevertsIfInsufficientBalance() public {
        vm.prank(user);
        vault.deposit(50 ether);

        vm.prank(user);
        vm.expectRevert("insufficient");
        vault.withdraw(51 ether);
    }

    function test_WithdrawRevertsWithZeroBalance() public {
        vm.prank(user);
        vm.expectRevert("insufficient");
        vault.withdraw(1 ether);
    }

    function testFuzz_DepositThenWithdraw(uint256 amount) public {
        amount = bound(amount, 1, 500 ether);

        vm.prank(user);
        vault.deposit(amount);

        vm.prank(user);
        vault.withdraw(amount);

        assertEq(vault.balances(user), 0);
        assertEq(token.balanceOf(user), 500 ether);
    }

    // ─────────────────────────────────────────────────────────────
    // Mint
    // ─────────────────────────────────────────────────────────────

    function test_MintUpdatesBalance() public {
        vm.prank(owner);
        vault.mint(user, 200 ether);

        assertEq(vault.balances(user), 200 ether);
    }

    function test_MintDoesNotTransferTokens() public {
        uint256 vaultBefore = token.balanceOf(address(vault));

        vm.prank(owner);
        vault.mint(user, 200 ether);

        assertEq(token.balanceOf(address(vault)), vaultBefore);
    }

    function test_MintRevertsForNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        vault.mint(user, 100 ether);
    }

    function testFuzz_Mint(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(owner);
        vault.mint(recipient, amount);

        assertEq(vault.balances(recipient), amount);
    }

    // ─────────────────────────────────────────────────────────────
    // Burn
    // ─────────────────────────────────────────────────────────────

    function test_BurnReducesBalance() public {
        vm.prank(owner);
        vault.mint(user, 100 ether);

        vm.prank(user);
        vault.burn(40 ether);

        assertEq(vault.balances(user), 60 ether);
    }

    function test_BurnDoesNotTransferTokens() public {
        vm.prank(owner);
        vault.mint(user, 100 ether);

        uint256 vaultBefore = token.balanceOf(address(vault));

        vm.prank(user);
        vault.burn(100 ether);

        assertEq(token.balanceOf(address(vault)), vaultBefore);
    }

    function test_BurnRevertsIfInsufficientBalance() public {
        vm.prank(user);
        vm.expectRevert();
        vault.burn(1 ether);
    }

    // ─────────────────────────────────────────────────────────────
    // Gasless — meta-transactions via ERC2771 forwarder
    // ─────────────────────────────────────────────────────────────

    function test_GaslessDeposit() public {
        bytes memory data = abi.encodeCall(GaslessVault.deposit, (100 ether));
        uint48 deadline   = uint48(block.timestamp + 1 hours);

        ERC2771Forwarder.ForwardRequestData memory req =
            _buildAndSignRequest(userKey, address(vault), data, deadline);

        vm.prank(relayer);
        forwarder.execute(req);

        assertEq(vault.balances(user), 100 ether);
    }

    function test_GaslessWithdraw() public {
        vm.prank(user);
        vault.deposit(100 ether);

        bytes memory data = abi.encodeCall(GaslessVault.withdraw, (100 ether));
        uint48 deadline   = uint48(block.timestamp + 1 hours);

        ERC2771Forwarder.ForwardRequestData memory req =
            _buildAndSignRequest(userKey, address(vault), data, deadline);

        vm.prank(relayer);
        forwarder.execute(req);

        assertEq(vault.balances(user), 0);
        assertEq(token.balanceOf(user), 500 ether);
    }

    function test_GaslessMintByOwner() public {
        bytes memory data = abi.encodeCall(GaslessVault.mint, (user, 50 ether));
        uint48 deadline   = uint48(block.timestamp + 1 hours);

        ERC2771Forwarder.ForwardRequestData memory req =
            _buildAndSignRequest(ownerKey, address(vault), data, deadline);

        vm.prank(relayer);
        forwarder.execute(req);

        assertEq(vault.balances(user), 50 ether);
    }

    function test_GaslessMintRevertsForNonOwner() public {
        bytes memory data = abi.encodeCall(GaslessVault.mint, (user, 50 ether));
        uint48 deadline   = uint48(block.timestamp + 1 hours);

        ERC2771Forwarder.ForwardRequestData memory req =
            _buildAndSignRequest(userKey, address(vault), data, deadline);

        vm.prank(relayer);
        vm.expectRevert();
        forwarder.execute(req);
    }

    function test_GaslessExpiredRequestReverts() public {
        bytes memory data = abi.encodeCall(GaslessVault.deposit, (100 ether));
        uint48 deadline   = uint48(block.timestamp - 1);

        ERC2771Forwarder.ForwardRequestData memory req =
            _buildAndSignRequest(userKey, address(vault), data, deadline);

        vm.prank(relayer);
        vm.expectRevert();
        forwarder.execute(req);
    }

    function test_GaslessReplayReverts() public {
        vm.prank(user);
        vault.deposit(200 ether);

        bytes memory data = abi.encodeCall(GaslessVault.withdraw, (10 ether));
        uint48 deadline   = uint48(block.timestamp + 1 hours);

        ERC2771Forwarder.ForwardRequestData memory req =
            _buildAndSignRequest(userKey, address(vault), data, deadline);

        vm.prank(relayer);
        forwarder.execute(req);

        vm.prank(relayer);
        vm.expectRevert();
        forwarder.execute(req);
    }

    // ─────────────────────────────────────────────────────────────
    // UUPS Upgrade
    // ─────────────────────────────────────────────────────────────

    function test_OwnerCanUpgrade() public {
        GaslessVault newImpl = new GaslessVault(address(forwarder));

        vm.prank(owner);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(vault.owner(), owner);
    }

    function test_NonOwnerCannotUpgrade() public {
        GaslessVault newImpl = new GaslessVault(address(forwarder));

        vm.prank(user);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newImpl), "");
    }

    function test_UpgradePreservesState() public {
        vm.prank(user);
        vault.deposit(100 ether);

        GaslessVault newImpl = new GaslessVault(address(forwarder));

        vm.prank(owner);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(vault.balances(user), 100 ether);
        assertEq(address(vault.token()), address(token));
        assertEq(vault.owner(), owner);
    }
}
