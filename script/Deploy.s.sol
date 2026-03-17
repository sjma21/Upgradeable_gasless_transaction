// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/GaslessVault.sol";
import "../src/TestToken.sol";

contract Deploy is Script {

    function run() external {

        vm.startBroadcast();

        ERC2771Forwarder forwarder = new ERC2771Forwarder("GaslessForwarder");
        TestToken token = new TestToken();

        GaslessVault implementation =
            new GaslessVault(address(forwarder));

        bytes memory initData =
            abi.encodeCall(GaslessVault.initialize, (address(token), msg.sender));

        ERC1967Proxy proxy =
            new ERC1967Proxy(address(implementation), initData);

        vm.stopBroadcast();
    }
}