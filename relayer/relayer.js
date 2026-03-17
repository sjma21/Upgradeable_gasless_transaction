const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const RPC_URL = "RPC_url";

const RELAYER_PRIVATE_KEY = "Relayer_Private_key";

const FORWARDER_ADDRESS = "0x3934B1836332B302e0De445C3111290d2c8D4C68";

const provider =
new ethers.JsonRpcProvider(RPC_URL);

const relayer =
new ethers.Wallet(
 RELAYER_PRIVATE_KEY,
 provider
);

const forwarderABI = [
"function execute((address from,address to,uint256 value,uint256 gas,uint48 deadline,bytes data,bytes signature) request) payable"
];

const forwarder =
new ethers.Contract(
 FORWARDER_ADDRESS,
 forwarderABI,
 relayer
);

async function main(){

 const file =
 JSON.parse(
  fs.readFileSync(
   path.join(__dirname,"request.json"),
   "utf8"
  )
 );

 const request = {
  from: file.request.from,
  to: file.request.to,
  value: BigInt(file.request.value),
  gas: BigInt(file.request.gas),
  deadline: BigInt(file.request.deadline),
  data: file.request.data,
  signature: file.request.signature
 };

 const tx =
 await forwarder.execute(
  request,
  {value:request.value}
 );

 console.log("tx:",tx.hash);

 await tx.wait();

 console.log("gasless executed");
}

main();
