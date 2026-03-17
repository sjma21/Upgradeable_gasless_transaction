const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const RPC_URL = "https://sepolia.optimism.io";

const USER_PRIVATE_KEY = "USER_PRIVATE_KEY";

const FORWARDER_ADDRESS = "0x3934B1836332B302e0De445C3111290d2c8D4C68";

const VAULT_ADDRESS = "0xe90766e5a0564680b3470EF43B4500EEF7CC6bd7";

const provider = new ethers.JsonRpcProvider(RPC_URL);

const wallet = new ethers.Wallet(USER_PRIVATE_KEY, provider);

const forwarderABI = [
 "function nonces(address) view returns(uint256)"
];

const forwarder = new ethers.Contract(
 FORWARDER_ADDRESS,
 forwarderABI,
 provider
);

async function main(){

 const nonce = await forwarder.nonces(wallet.address);

 const network = await provider.getNetwork();

 const iface = new ethers.Interface([
    "function withdraw(uint256)"
    ]);
  
    const data = iface.encodeFunctionData("withdraw", [30]);



 const deadline = BigInt(Math.floor(Date.now()/1000)+3600);

 const message = {
  from: wallet.address,
  to: VAULT_ADDRESS,
  value: 0n,
  gas: 200000n,
  nonce,
  deadline,
  data
 };

 const domain = {
  name: "GaslessForwarder",
  version: "1",
  chainId: network.chainId,
  verifyingContract: FORWARDER_ADDRESS
 };

 const types = {
  ForwardRequest:[
   {name:"from",type:"address"},
   {name:"to",type:"address"},
   {name:"value",type:"uint256"},
   {name:"gas",type:"uint256"},
   {name:"nonce",type:"uint256"},
   {name:"deadline",type:"uint48"},
   {name:"data",type:"bytes"}
  ]
 };

 const signature = await wallet.signTypedData(
  domain,
  types,
  message
 );

 const request = {
  from: message.from,
  to: message.to,
  value: message.value.toString(),
  gas: message.gas.toString(),
  deadline: message.deadline.toString(),
  data: message.data,
  signature
 };

 fs.writeFileSync(
  path.join(__dirname,"request.json"),
  JSON.stringify({request},null,2)
 );

 console.log("Request generated");
}

main();
