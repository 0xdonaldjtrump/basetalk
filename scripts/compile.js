const solc=require("solc"),fs=require("fs");
const input={language:"Solidity",sources:{"BaseTalk.sol":{content:fs.readFileSync("BaseTalk.sol","utf8")}},
settings:{optimizer:{enabled:true,runs:200},evmVersion:"paris",outputSelection:{"*":{"*":["abi","evm.bytecode.object"]}}}};
const out=JSON.parse(solc.compile(JSON.stringify(input)));
(out.errors||[]).forEach(e=>console.log(e.severity,e.formattedMessage));
const c=out.contracts["BaseTalk.sol"].BaseTalk;
fs.writeFileSync("build.json",JSON.stringify({abi:c.abi,bytecode:"0x"+c.evm.bytecode.object}));
console.log("bytes",c.evm.bytecode.object.length/2);
